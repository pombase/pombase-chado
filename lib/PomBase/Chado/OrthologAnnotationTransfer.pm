package PomBase::Chado::OrthologAnnotationTransfer;

=head1 NAME

PomBase::Chado::OrthologAnnotationTransfer - Transfer annotation
      using 1-1 orthologs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::OrthologAnnotationTransfer

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose;

use DateTime;

use Text::CSV;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has source_organism => (is => 'rw', init_arg => undef);
has dest_organism => (is => 'rw', init_arg => undef);
has source_organism_taxonid => (is => 'rw', init_arg => undef);
has dest_organism_taxonid => (is => 'rw', init_arg => undef);
has ev_codes_to_ignore => (is => 'rw', init_arg => undef);
has terms_to_ignore => (is => 'rw', init_arg => undef);

with 'PomBase::Role::OrthologMap';

sub BUILD
{
  my $self = shift;

  my $source_organism_taxonid = undef;
  my $dest_organism_taxonid = undef;
  my $ev_codes_to_ignore_string = undef;
  my $terms_to_ignore_string = undef;
  my $ortholog_filename = undef;

  my @opt_config = ("source-organism-taxonid=s" => \$source_organism_taxonid,
                    "dest-organism-taxonid=s" => \$dest_organism_taxonid,
                    "evidence-codes-to-ignore=s" => \$ev_codes_to_ignore_string,
                    "terms-to-ignore=s" => \$terms_to_ignore_string,
                    "ortholog-file=s" => \$ortholog_filename,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }


  if (!defined $source_organism_taxonid || length $source_organism_taxonid == 0) {
    die "no --source-organism-taxonid passed to the TransferNamesAndProducts loader\n";
  }

  my $source_organism = $self->find_organism_by_taxonid($source_organism_taxonid);

  if (!defined $source_organism) {
    die "can't find organism with taxon ID: $source_organism_taxonid\n";
  }

  $self->source_organism_taxonid($source_organism_taxonid);
  $self->source_organism($source_organism);

  if (!defined $dest_organism_taxonid || length $dest_organism_taxonid == 0) {
    die "no --dest-organism-taxonid passed to the TransferNamesAndProducts loader\n";
  }

  my $dest_organism = $self->find_organism_by_taxonid($dest_organism_taxonid);

  if (!defined $dest_organism) {
    die "can't find organism with taxon ID: $dest_organism_taxonid\n";
  }

  $self->dest_organism_taxonid($dest_organism_taxonid);
  $self->dest_organism($dest_organism);

  if (!defined $dest_organism_taxonid || length $dest_organism_taxonid == 0) {
    die "no --dest-organism-taxonid passed to the transfer-gaf-annotations loader\n";
  }


  my %ev_codes_to_ignore = ();

  if (defined $ev_codes_to_ignore_string && length $ev_codes_to_ignore_string > 0) {
    map {
      $ev_codes_to_ignore{$_} = 1;
    } split /,/, $ev_codes_to_ignore_string;
  }

  $self->ev_codes_to_ignore(\%ev_codes_to_ignore);


  my %terms_to_ignore = ();

  if (defined $terms_to_ignore_string && length $terms_to_ignore_string > 0) {
    map {
      my $term_id = $_;
      $terms_to_ignore{$term_id} = 1;

      my $ignore_term = $self->find_cvterm_by_term_id($term_id);

      my @child_terms = $self->all_child_terms($ignore_term, 'is_a');

      map {
        my $id = $_->dbxref()->db()->name() . ':' . $_->dbxref()->accession();
        $terms_to_ignore{$id} = 1;
      } @child_terms;

    } split /,/, $terms_to_ignore_string;
  }

  $self->terms_to_ignore(\%terms_to_ignore);
}


sub process {
  my $self = shift;

  my $dt = DateTime->now();

  open my $fh, '<-:encoding(UTF-8)' or die;

  my $csv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1, binary => 1 });

  my @column_names = qw(DB DB_object_id DB_object_symbol Qualifier GO_id DB_reference Evidence_code With_or_from Aspect DB_object_name DB_object_synonym DB_object_type Taxon Date Assigned_by Annotation_extension Gene_product_form_id);

  $csv->column_names(@column_names);

  my %ev_codes_to_ignore = %{$self->ev_codes_to_ignore()};
  my %terms_to_ignore = %{$self->terms_to_ignore()};
  my %orthologs =
    $self->reverse_ortholog_map($self->source_organism(), $self->dest_organism());

  my %seen_output_lines = ();

  while (defined (my $line = $fh->getline())) {
    next if $line =~ /^\s*!/;

    if (!$csv->parse($line)) {
      die "Parse error at line $.: ", $csv->error_input(), "\n";
    }

    my %columns = ();

    @columns{ $csv->column_names() } = $csv->fields();

    next if $columns{Qualifier} eq 'NOT';

    my $taxonid = $columns{"Taxon"};

    if (!defined $taxonid) {
      warn "Taxon missing - skipping\n";
      next;
    }

    $taxonid =~ s/taxon://ig;

    if ($taxonid !~ /^\d+$/) {
      warn "Taxon is not a number: $taxonid - skipping\n";
      next;
    }

    if ($taxonid != $self->source_organism_taxonid()) {
      warn "Wrong taxon ID: $taxonid - skipping\n";
      next;
    }

    my $evidence_code = $columns{Evidence_code};

    if ($ev_codes_to_ignore{$evidence_code}) {
      next;
    }

    if ($terms_to_ignore{$columns{GO_id}}) {
      next;
    }

    $columns{Evidence_code} = 'IEA';

    my $source_db_object = $columns{DB_object_id};

    my $dest_db_objects = $orthologs{$source_db_object};

    if (!defined $dest_db_objects) {
      next;
    }

    $columns{Taxon} = 'taxon:' . $self->dest_organism_taxonid();
    $columns{With_or_from} = $columns{DB} . ":" . $source_db_object;
    $columns{DB_object_synonym} = '';

    $columns{DB_reference} = 'GO_REF:0000107';
    $columns{Annotation_extension} = '';
    $columns{Gene_product_form_id} = '';

    my $date_str = $dt->ymd('');

    $columns{Date} = $date_str;

    for my $dest_db_object (@$dest_db_objects) {
      $columns{DB_object_id} = $dest_db_object;
      my $out_line =
        join "\t", map {
          $columns{$_};
        } @column_names;

      if (!exists $seen_output_lines{$out_line}) {
        print "$out_line\n";
        $seen_output_lines{$out_line} = 1;
      }
    }
  }
}

1;
