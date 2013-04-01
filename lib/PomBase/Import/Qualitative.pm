package PomBase::Import::Qualitative;

=head1 NAME

PomBase::Import::Qualitative - Import qualitative gene expression data

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Qualitative

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

use Text::CSV;
use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');
has organism_taxonid => (is => 'rw', init_arg => undef);
has organism => (is => 'rw', init_arg => undef);

method BUILD
{
  my $organism_taxonid = undef;

  my @opt_config = ('organism_taxonid=s' => \$organism_taxonid);
  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $organism_taxonid) {
    die "the --organism_taxonid argument is required\n";
  }

  $self->organism_taxonid($organism_taxonid);
  my $organism = $self->find_organism_by_taxonid($organism_taxonid);
  $self->organism($organism);
}


method load($fh)
{
  my $chado = $self->chado();

  my $organism = $self->organism();

  my $rna_level_cvterm = $self->get_cvterm('gene_ex', 'RNA level');
  my $protein_level_cvterm = $self->get_cvterm('gene_ex', 'protein level');

  my $csv = Text::CSV->new({ sep_char => "\t" });

  $csv->column_names ($csv->getline($fh));

  my $evidence_code = "ECO:0000006";
  my $long_evidence =
    $self->config()->{evidence_types}->{$evidence_code}->{name};

  while (my $columns_ref = $csv->getline_hr($fh)) {
    my $systematic_id = $columns_ref->{"Systematic ID"};
    my $type = $columns_ref->{"Type"};
    my $during = $columns_ref->{"During"};
    my $average_copies_per_cell = $columns_ref->{"Average copies per cell"};
    if ($average_copies_per_cell eq 'NA') {
      $average_copies_per_cell = undef;
    }
    my $range = $columns_ref->{"Range"};
    if ($range eq 'NA') {
      $range = undef;
    }
    my $qual_gene_ex_cell_distribution = $columns_ref->{"Evidence"};
    if (lc $qual_gene_ex_cell_distribution eq 'population' or
        lc $qual_gene_ex_cell_distribution eq 'population wide') {
      $qual_gene_ex_cell_distribution = 'population_wide';
    } else {
      if (lc $qual_gene_ex_cell_distribution eq 'single cell') {
        $qual_gene_ex_cell_distribution = 'single cell';
      } else {
        die qq(text in "Evidence" column not recognised: $qual_gene_ex_cell_distribution\n);
      }
    }
    my $conditions = $columns_ref->{"Condition"};
    my $source = $columns_ref->{"Source"};

    my $term;

    if ($type eq 'RNA') {
      $term = $rna_level_cvterm;
    } else {
      if ($type eq 'protein') {
        $term = $protein_level_cvterm;
      } else {
        die "Unknown type: $type\n";
      }
    }

    my $feature;
    try {
      $feature = $self->find_chado_feature($systematic_id, 1, 0, $organism);
    } catch {
      warn "skipping annotation: $_";
    };
    next unless defined $feature;

    my $pub = $self->find_or_create_pub($source);

    my $feature_cvterm =
      $self->create_feature_cvterm($feature, $term, $pub, 0);

    $self->add_feature_cvtermprop($feature_cvterm, 'qual_gene_ex_during',
                                  $during);
    $self->add_feature_cvtermprop($feature_cvterm, 'qual_gene_ex_avg_copies_per_cell',
                                  $average_copies_per_cell);
    $self->add_feature_cvtermprop($feature_cvterm, 'qual_gene_ex_copies_per_cell',
                                  $range);
    $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                  $long_evidence);
    $self->add_feature_cvtermprop($feature_cvterm, 'qual_gene_ex_cell_distribution',
                                  $qual_gene_ex_cell_distribution);

    my @conditions = split /\s*,\s*/, $conditions;
    for (my $i = 0; $i < @conditions; $i++) {
      my $condition = $conditions[$i];
      $self->add_feature_cvtermprop($feature_cvterm, 'condition', $condition, $i);
    }
  }
}
