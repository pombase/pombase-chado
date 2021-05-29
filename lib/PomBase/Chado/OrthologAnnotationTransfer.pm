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

use perl5i::2;
use Moose;

use DateTime;

use Text::CSV;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ConfigUser';

has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has source_organism_taxonid => (is => 'rw', init_arg => undef);
has dest_organism_taxonid => (is => 'rw', init_arg => undef);
has one_to_one_orthologs => (is => 'rw', init_arg => undef);
has ev_codes_to_ignore => (is => 'rw', init_arg => undef);

sub BUILD
{
  my $self = shift;

  my $source_organism_taxonid = undef;
  my $dest_organism_taxonid = undef;
  my $ev_codes_to_ignore_string = undef;
  my $ortholog_filename = undef;

  my @opt_config = ("source-organism-taxonid=s" => \$source_organism_taxonid,
                    "dest-organism-taxonid=s" => \$dest_organism_taxonid,
                    "evidence-codes-to-ignore=s" => \$ev_codes_to_ignore_string,
                    "ortholog-file=s" => \$ortholog_filename,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $source_organism_taxonid || length $source_organism_taxonid == 0) {
    die "no --source-organism-taxonid passed to the transfer-gaf-annotations loader\n";
  }

  $self->source_organism_taxonid($source_organism_taxonid);


  if (!defined $dest_organism_taxonid || length $dest_organism_taxonid == 0) {
    die "no --dest-organism-taxonid passed to the transfer-gaf-annotations loader\n";
  }

  $self->dest_organism_taxonid($dest_organism_taxonid);


  my %ev_codes_to_ignore = ();

  if (defined $ev_codes_to_ignore_string && length $ev_codes_to_ignore_string > 0) {
    map {
      $ev_codes_to_ignore{$_} = 1;
    } split /,/, $ev_codes_to_ignore_string;
  }

  $self->ev_codes_to_ignore(\%ev_codes_to_ignore);

  if (!defined $ortholog_filename || length $ortholog_filename == 0) {
    die "no --ortholog-file passed to the transfer-gaf-annotations loader\n";
  }

  my %identifier_counts = ();

  my @raw_ortholog_rows = ();

  open my $orth_file, '<', $ortholog_filename or
    die qq|can't open "$ortholog_filename": $!\n|;

  while (defined (my $line = <$orth_file>)) {
    chomp $line;

    my @bits = split /\t/, $line;

    if (@bits >= 2) {
      $identifier_counts{$bits[0]}++;
      $identifier_counts{$bits[1]}++;
      push @raw_ortholog_rows, \@bits;
    }
  }

  my %one_to_one_orthologs = ();

  map {
    if ($identifier_counts{$_->[0]} == 1 && $identifier_counts{$_->[1]} == 1) {
      $one_to_one_orthologs{$_->[1]} = $_->[0];
    }
  } @raw_ortholog_rows;

  $self->one_to_one_orthologs(\%one_to_one_orthologs);
}


method process() {
  my $dt = DateTime->now();

  open my $fh, '<-' or die;

  my $csv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  my @column_names = qw(DB DB_object_id DB_object_symbol Qualifier GO_id DB_reference Evidence_code With_or_from Aspect DB_object_name DB_object_synonym DB_object_type Taxon Date Assigned_by Annotation_extension Gene_product_form_id);

  $csv->column_names(@column_names);

  my %ev_codes_to_ignore = %{$self->ev_codes_to_ignore()};
  my %one_to_one_orthologs = %{$self->one_to_one_orthologs()};

  while (defined (my $line = $fh->getline())) {
    next if $line =~ /^\s*!/;

    if (!$csv->parse($line)) {
      die "Parse error at line $.: ", $csv->error_input(), "\n";
    }

    my %columns = ();

    @columns{ $csv->column_names() } = $csv->fields();


    my $taxonid = $columns{"Taxon"};

    if (!defined $taxonid) {
      warn "Taxon missing - skipping\n";
      next;
    }

    $taxonid =~ s/taxon://ig;

    if (!$taxonid->is_integer()) {
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

    $columns{Evidence_code} = 'IEA';

    my $source_db_object_id = $columns{DB_object_id};

    my $dest_db_object_id = $one_to_one_orthologs{$source_db_object_id};

    if (!defined $dest_db_object_id) {
      next;
    }

    $columns{DB_object_id} = $dest_db_object_id;
    $columns{Taxon} = 'taxon:' . $self->dest_organism_taxonid();
    $columns{With_or_from} = $columns{DB} . ":" . $source_db_object_id;
    $columns{DB_object_synonym} = '';

    $columns{DB_reference} = 'GO_REF:0000107';
    $columns{Annotation_extension} = '';
    $columns{Gene_product_form_id} = '';

    my $date_str = $dt->ymd('');

    $columns{Date} = $date_str;

    my $out_line =
      join "\t", map {
        $columns{$_};
      } @column_names;

    print "$out_line\n";
  }
}
