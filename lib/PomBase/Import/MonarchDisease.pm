package PomBase::Import::MonarchDisease;

=head1 NAME

PomBase::Import::MonarchDisease - Read disease associations from Monarch, map
    to pombe using human orthologs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::MonarchDisease

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2024 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Text::Trim qw(trim);

use Moose;

use Text::CSV;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::CvtermpropStorer';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');

has destination_taxonid => (is => 'rw', init_arg => undef);
has add_qualifier => (is => 'rw', init_arg => undef);
has monarch_reference => (is => 'rw', init_arg => undef);
has human_ortholog_map => (is => 'rw', init_arg => undef);

sub BUILD {
  my $self = shift;
  my $destination_taxonid = undef;
  my $add_qualifier = undef;
  my $monarch_reference = undef;

  my @opt_config = ('destination-taxonid=s' => \$destination_taxonid,
                    'add-qualifier=s' => \$add_qualifier,
                    'monarch-reference=s' => \$monarch_reference);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $destination_taxonid) {
    die "the --destination-taxonid argument is required\n";
  }

  $self->destination_taxonid($destination_taxonid);

  if (!defined $monarch_reference) {
    die "the --monarch-reference argument is required\n";
  }

  $self->monarch_reference($monarch_reference);

  if (defined $add_qualifier) {
    $self->add_qualifier($add_qualifier);
  }

  my $chado = $self->chado();

  my $dest_organism = $self->find_organism_by_taxonid($destination_taxonid);
  my $human = $self->find_organism_by_common_name('human');

  my $orthologs_rs = $chado->resultset('Sequence::FeatureRelationship')
    ->search({
      -or => [
        -and => {
          'subject.organism_id' => $dest_organism->organism_id(),
          'object.organism_id' => $human->organism_id(),
        },
        -and => {
          'subject.organism_id' => $human->organism_id(),
          'object.organism_id' => $dest_organism->organism_id(),
        },
      ]
    }, { join => ['subject', 'object'] });

  my %human_ortholog_map = ();

  while (defined (my $ortholog_rel = $orthologs_rs->next())) {
    my $dest_gene = undef;
    my $human_gene = undef;

    if ($ortholog_rel->subject()->organism_id() == $human->organism_id()) {
      $dest_gene = $ortholog_rel->object();
      $human_gene = $ortholog_rel->subject();
    } else {
      $human_gene = $ortholog_rel->object();
      $dest_gene = $ortholog_rel->subject();
    }

    push @{$human_ortholog_map{$human_gene->uniquename()}}, $dest_gene;
  }

  $self->human_ortholog_map(\%human_ortholog_map);
}

my %details_by_do_id = ();

sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();

  my $tsv = Text::CSV->new({ sep_char => "\t" });

  my $pub = $self->find_or_create_pub($self->monarch_reference());

  my $add_qualifier = $self->add_qualifier();

  my %seen_annotations = ();

  while (my $columns_ref = $tsv->getline($fh)) {
    if (@$columns_ref == 1 && length(trim($columns_ref->[0])) == 0) {
      # empty line
      next;
    }

    if (@$columns_ref < 19) {
      warn "needed 19 columns, got ", scalar(@$columns_ref),
        " in Monarch input file line $., ignoring\n";
      next;
    }

 my ($hgnc_gene_id, $human_gene_name, $subject_category, $subject_taxon,
     $subject_taxon_label, $negated, $predicate, $mondo_id) =
       map { trim($_) || undef } @$columns_ref;

    if ($hgnc_gene_id eq 'subject') {
      # header
      next;
    }

    my $dest_genes = $self->human_ortholog_map()->{$hgnc_gene_id};

    if (defined $dest_genes) {
      my $dest_genes_uniquenames = join ',', map { $_->uniquename(); } @{$dest_genes};

      if ($mondo_id !~ /^MONDO:/) {
        warn qq|"$mondo_id" doesn't look like a MONDO ID - skipping\n|;
        next;
      }

      my $cvterm = $self->find_cvterm_by_term_id($mondo_id);

      if (!defined $cvterm) {
        $cvterm = $self->find_cvterm_by_term_id($mondo_id,
                                                { include_obsolete => 1 });

        if ($cvterm) {
          my $replaced_by_prop = $cvterm->cvtermprops()
            ->search({ 'type.name' => 'replaced_by' },
                     { join => 'type' })
            ->first();

          if (defined $replaced_by_prop) {
            warn "$mondo_id is obsolete (replaced by: ",
              $replaced_by_prop->value(), ") - skipping annotation for ",
              "$dest_genes_uniquenames\n";
          }

          my $consider_prop = $cvterm->cvtermprops()
            ->search({ 'type.name' => 'consider' },
                     { join => 'type' })
            ->first();

          if (defined $consider_prop) {
            warn "$mondo_id is obsolete (consider: ",
              $consider_prop->value(), ") - skipping annotation for ",
              "$dest_genes_uniquenames\n";
          }

          if (!defined $replaced_by_prop && !defined $consider_prop) {
            warn qq|$mondo_id is obsolete (no "replaced_by" or "consider" tag) - skipping annotation for |,
              "$dest_genes_uniquenames\n";
          }
        } else {
          warn "could not find cvterm for $mondo_id - skipping annotation for ",
            "$dest_genes_uniquenames\n";
        }

        next;
      }

      if (!exists $details_by_do_id{$mondo_id}) {
        $details_by_do_id{$mondo_id} = $cvterm;
      }

      for my $dest_gene (@$dest_genes) {
        my $key = "$mondo_id -> " . $dest_gene->uniquename();

        if (!$seen_annotations{$key}) {
          my $feature_cvterm = $self->create_feature_cvterm($dest_gene, $cvterm, $pub, 0);
          if (defined $add_qualifier) {
            $self->add_feature_cvtermprop($feature_cvterm, 'qualifier', $add_qualifier);
          }
          $self->add_feature_cvtermprop($feature_cvterm, 'annotation_throughput_type',
                                        'non-experimental');
          $seen_annotations{$key} = 1;
        }
      }
    } else {
      # no pombe ortholog
    }
  }

  while (my ($mondo_id, $mondo_cvterm) = each %details_by_do_id) {
    my $cvterm = $mondo_cvterm;
  }
}

1;
