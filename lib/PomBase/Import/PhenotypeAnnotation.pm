package PomBase::Import::PhenotypeAnnotation;

=head1 NAME

PomBase::Import::PhenotypeAnnotation - Code for loading PomBase phenotype
                                       annotation format files

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::PhenotypeAnnotation

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

use PomBase::Chado::ExtensionProcessor;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::PhenotypeFeatureFinder';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');

has extension_processor => (is => 'ro', init_arg => undef, lazy_build => 1);

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
  my $config = $self->config();

  my $csv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  $csv->column_names(qw(gene_systemtic_id fypo_id allele_description geneotype strain_background gene_name allele_name allele_synonym allele_type evidence conditions penetrance expressivity extension reference taxon date));

  while (my $columns_ref = $csv->getline_hr($fh)) {
    my $gene_systemtic_id = $columns_ref->{"gene_systemtic_id"};

    if ($gene_systemtic_id =~ /^#/) {
      next;
    }

    my $fypo_id = $columns_ref->{"fypo_id"};
    my $allele_description = $columns_ref->{"allele_description"};
    my $geneotype = $columns_ref->{"geneotype"};
    my $strain_background = $columns_ref->{"strain_background"};
    my $gene_name = $columns_ref->{"gene_name"};
    my $allele_name = $columns_ref->{"allele_name"};
    my $allele_synonym = $columns_ref->{"allele_synonym"};
    my $allele_type = $columns_ref->{"allele_type"};
    my $evidence = $columns_ref->{"evidence"};
    my $conditions = $columns_ref->{"conditions"};
    my $penetrance = $columns_ref->{"penetrance"};
    my $expressivity = $columns_ref->{"expressivity"};
    my $extension = $columns_ref->{"extension"};
    my $reference = $columns_ref->{"reference"};
    my $date = $columns_ref->{"date"};
    my $taxonid = $columns_ref->{"taxon"};

    if (!defined $taxonid) {
      warn "Taxon missing - skipping\n";
      next;
    }

    $taxonid =~ s/taxon://ig;

    if (!$taxonid->is_integer()) {
      warn "Taxon is not a number: $taxonid - skipping\n";
      next;
    }

    my $organism = $self->find_organism_by_taxonid($taxonid);

    if (!defined $organism) {
      warn "ignoring annotation for organism $taxonid\n";
      next;
    }

    my $long_evidence = $self->config()->{evidence_types}->{$evidence}->{name};

    if (length $penetrance > 0 &&
        !defined $self->find_cvterm_by_term_id($penetrance)) {
      warn "can't load annotation, $penetrance not found\n";
      next;
    }

    if (length $expressivity > 0 &&
        !defined $self->find_cvterm_by_term_id($expressivity)) {
      warn "can't load annotation, $expressivity not found\n";
      next;
    }

    my $gene = $self->find_chado_feature("$gene_systemtic_id", 1, 1, $organism);

    if (!defined $gene) {
      warn "gene ($gene_systemtic_id) not found - skipping row\n";
      next;
    }

    my $proc = sub {
      my $pub = $self->find_or_create_pub($reference);

      my $cvterm = $self->find_cvterm_by_term_id($fypo_id);

      if (!defined $cvterm) {
        warn "can't load annotation, $fypo_id not found in database\n";
        return;
      }

      my $gene_uniquename = $gene->uniquename();
      my $existing_gene_name = $gene->name() // '';

      if (length $gene_name > 0 && $gene_name ne $existing_gene_name) {
        warn qq|gene name from phenotype annotation file ("$gene_name") doesn't | .
          qq|match the existing name ("$existing_gene_name") for $gene_uniquename | .
          qq|- skipping|;
        return;
      }

      my $allele_data = {
        gene => {
          uniquename => $gene_uniquename,
          organism => $organism->genus() . ' ' . $organism->species(),
        },
        name => $allele_name,
        description => $allele_description,
        allele_type => $allele_type,
      };

      my $allele_feature = $self->get_allele($allele_data);

      my $feature_cvterm =
        $self->create_feature_cvterm($allele_feature, $cvterm, $pub, 0);

      $self->add_feature_cvtermprop($feature_cvterm, 'date', $date);
      if (length $penetrance > 0) {
        $self->add_feature_cvtermprop($feature_cvterm, 'penetrance', $penetrance);
      }
      if (length $expressivity > 0) {
        $self->add_feature_cvtermprop($feature_cvterm, 'expressivity',
                                      $expressivity);
      }
      $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                   $long_evidence);

      my @conditions = split /\s*\|\s*/, $conditions;
      for (my $i = 0; $i < @conditions; $i++) {
        my $condition = $conditions[$i];
        $self->add_feature_cvtermprop($feature_cvterm, 'condition', $condition, $i);
      }

      if (defined $extension && length $extension > 0) {
        my ($out, $err) = capture {
          $self->extension_processor()->process_one_annotation($feature_cvterm, $extension);
        };
        if (length $out > 0) {
          die $out;
        }
        if (length $err > 0) {
          die $err;
        }
      }
    };

    try {
      $chado->txn_do($proc);
    } catch {
      warn "Failed to load row: $_\n";
    }
  }

  if (!$csv->eof()){
    $csv->error_diag();
  }

  return undef;
}

method results_summary($results)
{
  return '';
}

1;
