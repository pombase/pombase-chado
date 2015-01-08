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
use Try::Tiny;
use Text::CSV;
use IO::Handle;

use PomBase::Chado::ExtensionProcessor;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
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

my $fypo_extensions_cv_name = 'fypo_extensions';

method load($fh)
{
  my $chado = $self->chado();
  my $config = $self->config();

  my $processor = $self->extension_processor();

  my $csv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  $csv->column_names(qw(gene_systemtic_id fypo_id allele_description expression
                        parental_strain strain_background genotype_description
                        gene_name allele_name allele_synonym allele_type
                        evidence conditions penetrance expressivity extension
                        reference taxon date illegal_extra_column));

  while (my $columns_ref = $csv->getline_hr($fh)) {
    my $gene_systemtic_id = $columns_ref->{"gene_systemtic_id"}->trim();

    if ($gene_systemtic_id =~ /^#/ ||
        ($. == 1 && $gene_systemtic_id =~ /Gene .*ID/)) {
      next;
    }

    if (length $gene_systemtic_id == 0) {
      warn "no value in the gene_systemtic_id column at line ", $fh->input_line_number(), " - skipping\n";
      next;
    }

    if ($columns_ref->{illegal_extra_column}) {
      warn "too many columns at line ", $fh->input_line_number(),
        " starting with: $columns_ref->{illegal_extra_column}\n";
      next;
    }

    my $fypo_id = $columns_ref->{"fypo_id"};
    my $allele_description = $columns_ref->{"allele_description"};
    my $genotype_description = $columns_ref->{"genotype_description"};
    my $strain_background = $columns_ref->{"strain_background"};
    my $gene_name = $columns_ref->{"gene_name"};
    my $allele_name = $columns_ref->{"allele_name"};
    my $allele_synonym = $columns_ref->{"allele_synonym"};
    my $allele_type = $columns_ref->{"allele_type"};

    if (!$allele_name) {
      if (lc $allele_type eq 'deletion') {
        $allele_name = ($gene_name || $gene_systemtic_id) . 'delta';
      }
    }

    my $evidence = $columns_ref->{"evidence"};
    my $conditions = $columns_ref->{"conditions"};
    my $penetrance = $columns_ref->{"penetrance"};
    my $expressivity = $columns_ref->{"expressivity"};
    my $extension = $columns_ref->{"extension"};
    my $reference = $columns_ref->{"reference"};
    my $date = $columns_ref->{"date"};
    my $taxonid = $columns_ref->{"taxon"};

    my $proc = sub {
      if (!defined $evidence || length $evidence == 0) {
        warn "no value in the evidence column at line ", $fh->input_line_number(), " - skipping\n";
        return;
      }

      if (!defined $taxonid) {
        warn "Taxon missing - skipping\n";
        return;
      }

      $taxonid =~ s/taxon://ig;

      if (!$taxonid->is_integer()) {
        warn "Taxon is not a number: $taxonid at line ", $fh->input_line_number(), " - skipping\n";
        return;
      }

      my $organism = $self->find_organism_by_taxonid($taxonid);

      if (!defined $organism) {
        warn "ignoring annotation for organism $taxonid at line ", $fh->input_line_number(), "\n";
        return;
      }

      my $long_evidence = $self->config()->{evidence_types}->{lc $evidence}->{name};

      if (!defined $long_evidence) {
        $long_evidence = $evidence;
        warn "can't load annotation, unknown evidence: $evidence at line ", $fh->input_line_number(), "\n";
      }

      if (length $penetrance > 0) {
        my $penetrance_cvterm = $self->find_cvterm_by_term_id($penetrance);

        if (defined $penetrance_cvterm) {
          if ($penetrance_cvterm->cv()->name() ne $fypo_extensions_cv_name) {
            warn "can't load annotation, '$penetrance' is not from the ",
              "$fypo_extensions_cv_name CV at line ", $fh->input_line_number(), "\n";
            return;
          }
        } else {
          warn "can't load annotation, $penetrance not found at line ",
            $fh->input_line_number(), " of PHAF file\n";
          return;
        }
      }

      if (length $expressivity > 0) {
        my $expressivity_cvterm = $self->find_cvterm_by_term_id($expressivity);

        if (defined $expressivity_cvterm) {
          if ($expressivity_cvterm->cv()->name() ne $fypo_extensions_cv_name) {
            warn "can't load annotation, '$expressivity' is not from the ",
              "$fypo_extensions_cv_name CV at line ", $fh->input_line_number(), "\n";
            return;
          }
        } else {
          warn "can't load annotation, $expressivity not found at line ",
            $fh->input_line_number(), " of PHAF file\n";
          return;
        }
      }

      my $gene = $self->find_chado_feature("$gene_systemtic_id", 1, 1, $organism);

      if (!defined $gene) {
        warn "gene ($gene_systemtic_id) not found - skipping line ", $fh->input_line_number(), "\n";
        return;
      }

      my $pub = $self->find_or_create_pub($reference);

      my $cvterm = undef;

      try {
        $cvterm = $self->find_cvterm_by_term_id($fypo_id);
      } catch {
        warn "find_cvterm_by_term_id failed: $_";
      };

      if (!defined $cvterm) {
        my $obsolete_cvterm = $self->find_cvterm_by_term_id($fypo_id, { include_obsolete => 1 });
        if (defined $obsolete_cvterm) {
          warn "can't load annotation, $fypo_id is an obsolete term, at line ", $fh->input_line_number(), "\n";
        } else {
          warn "can't load annotation, $fypo_id not found in database, at line ", $fh->input_line_number(), "\n";
        }
        return;
      }

      my $gene_uniquename = $gene->uniquename();
      my $existing_gene_name = $gene->name() // '';

      if (length $gene_name > 0 && $gene_name ne $existing_gene_name &&
          $gene_name ne $gene_uniquename) {
        warn qq|gene name from phenotype annotation file ("$gene_name") doesn't | .
          qq|match the existing name ("$existing_gene_name") for $gene_uniquename | .
          "at line ", $fh->input_line_number(), "\n";
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

      my @extension_bits = ();

      if (length $extension > 0) {
        push @extension_bits, $extension;
      }

      if (length $penetrance > 0) {
        push @extension_bits, "has_penetrance($penetrance)";
      }
      if (length $expressivity > 0) {
        push @extension_bits, "has_expressivity($expressivity)";
      }

      $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                   $long_evidence);

      my @conditions = split /\s*,\s*/, $conditions;
      for (my $i = 0; $i < @conditions; $i++) {
        my $condition = $conditions[$i];
        $self->add_feature_cvtermprop($feature_cvterm, 'condition', $condition, $i);
      }

      if (@extension_bits > 0) {
        my $extension_text = join ",", @extension_bits;
        my ($out, $err) = capture {
          $processor->process_one_annotation($feature_cvterm, $extension_text);
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
      warn "Failed to load line ", $fh->input_line_number(), ": $_\n";
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
