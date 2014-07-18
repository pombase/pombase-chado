package PomBase::Import::Quantitative;

=head1 NAME

PomBase::Import::Quantitative - Import quantitative gene expression data

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Quantitative

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

use PomBase::Chado::ExtensionProcessor;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');
has extension_processor => (is => 'ro', init_arg => undef, lazy => 1,
                            builder => '_build_extension_processor');

method _build_extension_processor
{
  my $processor = PomBase::Chado::ExtensionProcessor->new(chado => $self->chado(),
                                                          config => $self->config(),
                                                          pre_init_cache => 1,
                                                          verbose => $self->verbose());
  return $processor;
}

method load($fh)
{
  my $chado = $self->chado();

  my $rna_level_cvterm = $self->get_cvterm('gene_ex', 'RNA level');
  my $protein_level_cvterm = $self->get_cvterm('gene_ex', 'protein level');

  my $csv = Text::CSV->new({ sep_char => "\t" });

  $csv->column_names($csv->getline($fh));

  while (my $columns_ref = $csv->getline($fh)) {
    if (@$columns_ref == 1 && $columns_ref->[0]->trim()->length() == 0) {
      # empty line
      next;
    }

    my ($systematic_id, $gene_name, $type, $during, $average_copies_per_cell,
        $range, $evidence_code, $scale, $conditions, $pubmedid, $taxonid, $date) =
          map {
            my $trimmed = $_->trim();
            if (length $trimmed > 0) {
              $trimmed;
            } else {
              undef
            }
          } @$columns_ref;

    if (!defined $systematic_id) {
      die qq(mandatory column value for systematic ID missing at line $.\n);
    }
    if (!defined $type) {
      die qq(mandatory column value for feature type missing at line $.\n);
    }
    if (!defined $during) {
      die qq(mandatory column value for expression level missing at line $.\n);
    }
    if (!defined $average_copies_per_cell) {
      die qq(mandatory column value for average copies per cell missing at line $.\n);
    }
    if (!defined $evidence_code) {
      die qq(mandatory column value for evidence missing at line $.\n);
    }
    if (!defined $scale) {
      die qq(mandatory column value for scale missing at line $.\n);
    }
    if (!defined $pubmedid) {
      die qq(mandatory column value for reference missing at line $.\n);
    }
    if (!defined $taxonid) {
      die qq(mandatory column value for taxon missing at line $.\n);
    }
    if (!defined $date) {
      die qq(mandatory column value for date missing at line $.\n);
    }

    if ($average_copies_per_cell eq 'ND') {
      $average_copies_per_cell = undef;
    }

    if (defined $average_copies_per_cell) {
      if ($average_copies_per_cell !~ /^(?:[><])?\d+(?:\.\d+)?$/) {
        warn "skipping this annotation:\n@$columns_ref\n" .
          "because copies per cell must be a positive " .
          "floating point number with an optional '>' or '<' at the start\n";
        next;
      }
    }

    if (defined $range && $range eq 'NA') {
      $range = undef;
    }
    my $lc_scale = lc $scale;
    if ($lc_scale eq 'population' or
        $lc_scale eq 'population wide') {
      $scale = 'population_wide';
    } else {
      if ($lc_scale eq 'single cell' or $lc_scale eq 'single_cell') {
        $scale = 'single_cell';
      } else {
        die qq(text in "Scale" column not recognised: $scale\n);
      }
    }

    my $annotation_extension = "during($during)";

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

    my $organism = $self->find_organism_by_taxonid($taxonid);

    my $feature;
    try {
      $feature = $self->find_chado_feature($systematic_id, 1, 0, $organism);
    } catch {
      warn "skipping annotation: $_";
    };
    next unless defined $feature;

    if (defined $gene_name && defined $feature->name() &&
        $feature->name() ne $gene_name) {
      warn qq(gene name "$gene_name" from the input file doesn't match ) .
        qq(the gene name for $systematic_id from Chado ") . $feature->name() .
        qq("\n);
      next;
    }

    my $pub = $self->find_or_create_pub($pubmedid);

    my $feature_cvterm =
      $self->create_feature_cvterm($feature, $term, $pub, 0);

    if (defined $average_copies_per_cell) {
      $self->add_feature_cvtermprop($feature_cvterm, 'quant_gene_ex_avg_copies_per_cell',
                                    $average_copies_per_cell);
    }
    if (defined $range) {
      $self->add_feature_cvtermprop($feature_cvterm, 'quant_gene_ex_copies_per_cell',
                                    $range);
    }

    my $long_evidence =
      $self->config()->{evidence_types}->{$evidence_code}->{name};
    if (!defined $long_evidence) {
      die "unknown evidence code: $evidence_code at line $.\n";
    }
    $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                  $long_evidence);
    $self->add_feature_cvtermprop($feature_cvterm, 'scale',
                                  $scale);

    my @conditions = split /\s*,\s*/, $conditions;
    for (my $i = 0; $i < @conditions; $i++) {
      my $condition = $conditions[$i];
      $self->add_feature_cvtermprop($feature_cvterm, 'condition', $condition, $i);
    }

    $self->extension_processor()->process_one_annotation($feature_cvterm, $annotation_extension);
  }
}
