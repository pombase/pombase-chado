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

use strict;
use warnings;
use Carp;

use Text::Trim qw(trim);
use Try::Tiny;

use Capture::Tiny qw(capture);

use Moose;
use Try::Tiny;
use Text::CSV;
use IO::Handle;

use PomBase::Chado::ExtensionProcessor;
use PomBase::Chado::GenotypeCache;

use Getopt::Long qw(GetOptionsFromArray);

has genotype_cache => (is => 'ro', init_arg => undef,
                       lazy_build => 1,
                       isa => 'PomBase::Chado::GenotypeCache');

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
with 'PomBase::Role::LegacyAlleleHandler';
with 'PomBase::Role::Embl::FeatureRelationshippropStorer';
with 'PomBase::Role::PhenotypeFeatureFinder';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');

has extension_processor => (is => 'ro', init_arg => undef, lazy_build => 1);

has throughput_type => (is => 'rw', init_arg => undef);

sub BUILD
{
  my $self = shift;

  my $throughput_type = undef;

  my @opt_config = ("throughput-type=s" => \$throughput_type);

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (defined $throughput_type) {
    if ($throughput_type ne 'high throughput' && $throughput_type ne 'low throughput') {
      die "unknown --throughput-type argument: $throughput_type";
    }
  } else {
    warn "no --throughput-type passed to importer, assuming high-throughput\n";
    $throughput_type = 'high throughput';
  }

  $self->throughput_type($throughput_type);
}

sub _build_extension_processor {
  my $self = shift;
  my $processor = PomBase::Chado::ExtensionProcessor->new(chado => $self->chado(),
                                                          config => $self->config(),
                                                          pre_init_cache => 1,
                                                          verbose => $self->verbose());
  return $processor;
}

sub _build_genotype_cache {
  my $self = shift;
  return PomBase::Chado::GenotypeCache->new(chado => $self->chado());
}

my $fypo_extensions_cv_name = 'fypo_extensions';


sub _store_annotation {
  my $self = shift;
  my $genotype_feature = shift;
  my $cvterm = shift;
  my $pub = shift;
  my $date = shift;
  my $extension = shift;
  my $penetrance = shift;
  my $severity = shift;
  my $long_evidence = shift;
  my $conditions = shift;

  my @split_ext_parts = ("");

  if ($extension) {
    @split_ext_parts = sort split /(?<=\))\|/, $extension;
  }

  for my $split_ext (@split_ext_parts) {

    my $feature_cvterm =
      $self->create_feature_cvterm($genotype_feature, $cvterm, $pub, 0);

    $self->add_feature_cvtermprop($feature_cvterm, 'date', $date);

    $self->add_feature_cvtermprop($feature_cvterm, 'annotation_throughput_type',
                                  $self->throughput_type());

    my @extension_bits = ();

    if (length $split_ext > 0) {
      push @extension_bits, $split_ext;
    }

    if (length $penetrance > 0) {
      push @extension_bits, "has_penetrance($penetrance)";
    }
    if (length $severity > 0) {
      push @extension_bits, "has_severity($severity)";
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
        my $processor = $self->extension_processor();

        $processor->process_one_annotation($feature_cvterm, $extension_text);
      };
      if (length $out > 0) {
        die $out;
      }
      if (length $err > 0) {
        die $err;
      }
    }
  }
}


sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $csv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  $csv->column_names(qw(gene_systemtic_id fypo_id allele_description expression
                        parental_strain strain_background genotype_description
                        gene_name allele_name allele_synonym allele_type
                        evidence conditions penetrance severity extension
                        reference taxon date ploidy illegal_extra_column));

  while (my $columns_ref = $csv->getline_hr($fh)) {
    my $gene_systemtic_id = trim($columns_ref->{"gene_systemtic_id"});

    if ($gene_systemtic_id =~ /^#/ ||
        $gene_systemtic_id =~ /^#?(Gene .*ID|systematic)/i) {
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
    my $expression = ucfirst $columns_ref->{"expression"};
    my $genotype_description = $columns_ref->{"genotype_description"};
    my $strain_background = $columns_ref->{"strain_background"};
    my $gene_name = $columns_ref->{"gene_name"};
    my $allele_name = $columns_ref->{"allele_name"};
    my $allele_synonym = $columns_ref->{"allele_synonym"};
    my $allele_type = $columns_ref->{"allele_type"};
    my $evidence = $columns_ref->{"evidence"};
    my $conditions = $columns_ref->{"conditions"};
    my $penetrance = $columns_ref->{"penetrance"};
    my $severity = $columns_ref->{"severity"};
    my $extension = $columns_ref->{"extension"};
    my $reference = $columns_ref->{"reference"};
    my $date = $columns_ref->{"date"};
    $date =~ s/^\s*(\d\d\d\d)-?(\d\d)-?(\d\d)\s*$/$1-$2-$3/;

    my $taxonid = $columns_ref->{"taxon"};

    if (!defined $taxonid) {
      warn "Taxon missing, not enough columns - skipping\n";
      return;
    }

    $taxonid =~ s/taxon://ig;

    if ($taxonid  !~ /^\d+$/) {
      warn "Taxon is not a number: $taxonid at line ", $fh->input_line_number(), " - skipping\n";
      return;
    }

    my $ploidiness = $columns_ref->{"ploidy"} || "haploid";

    my $proc = sub {
      my $organism = $self->find_organism_by_taxonid($taxonid);

      if (!defined $organism) {
        warn "ignoring annotation for organism $taxonid at line ", $fh->input_line_number(), "\n";
        return;
      }

      my $gene = $self->find_chado_feature("$gene_systemtic_id", 1, 1, $organism);

      if (!defined $gene) {
        warn "gene ($gene_systemtic_id) not found - skipping line ", $fh->input_line_number(), "\n";
        return;
      }

      if (!$allele_name) {
        if (lc $allele_type eq 'deletion') {
          $allele_name = ($gene->name() || $gene_systemtic_id) . 'delta';
          if ($expression && $expression ne 'Null') {
            warn qq(expression "$expression" for $allele_name at line ),
              $fh->input_line_number(), qq( should be "Null"\n);
          } else {
            $expression = 'Null';
          }
        }
        if ($allele_type =~ /wild[\s_]type/i) {
          $allele_name = ($gene->name() || $gene_systemtic_id) . '+';
        }
      }

      if (!defined $evidence || length $evidence == 0) {
        warn "no value in the evidence column at line ", $fh->input_line_number(), " - skipping\n";
        return;
      }

      my $long_evidence = $self->config()->{evidence_types}->{lc $evidence}->{name};

      if (!defined $long_evidence) {
        $long_evidence = $evidence;
        warn "can't load annotation, unknown evidence: $evidence at line ", $fh->input_line_number(), "\n";
      }

      if (length $penetrance > 0) {
        if ($penetrance !~ /^[\d\.]+\%$/) {
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
      }

      if (length $severity > 0) {
        my $severity_cvterm = $self->find_cvterm_by_term_id($severity);

        if (defined $severity_cvterm) {
          if ($severity_cvterm->cv()->name() ne $fypo_extensions_cv_name) {
            warn "can't load annotation, '$severity' is not from the ",
              "$fypo_extensions_cv_name CV at line ", $fh->input_line_number(), "\n";
            return;
          }
        } else {
          warn "can't load annotation, $severity not found at line ",
            $fh->input_line_number(), " of PHAF file\n";
          return;
        }
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

      if ($gene_name &&
          $gene_name ne $existing_gene_name &&
          $gene_name ne $gene_uniquename) {
        warn qq|gene name from phenotype annotation file ("$gene_name") doesn't | .
          qq|match the existing name ("$existing_gene_name") for $gene_uniquename | .
          "at line ", $fh->input_line_number(), "\n";
      }

      if (lc $allele_type eq 'deletion') {
        $allele_name = ($existing_gene_name || $gene_uniquename) . 'delta';
      }

      if (lc $allele_type =~ /wild_?type/) {
        $allele_name = ($existing_gene_name || $gene_uniquename) . '+';
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

      $expression = undef if $expression && lc $expression eq 'null';

      my $background_description =
        ($genotype_description // '') . ' ' . ($strain_background // '');

      if ($background_description =~ /^\s*$/) {
        $background_description = undef;
      }

      my $genotype_feature;

      if ($ploidiness eq 'haploid') {
        $genotype_feature =
          $self->get_genotype_for_allele($background_description, $allele_data, $expression);
      } else {
        if ($ploidiness eq 'homozygous diploid') {
          my $allele = $self->get_allele($allele_data);

          my $genotype_identifier = $self->get_genotype_uniquename();

          my $locus = "$genotype_identifier-$reference-locus-1";
          my @alleles = (
            { allele => $allele, expression => $expression, genotype_locus => $locus },
            { allele => $allele, expression => $expression, genotype_locus => $locus },
          );

          $genotype_feature =
            $self->get_genotype($genotype_identifier, undef,
                                $background_description, \@alleles);

        } else {
          die qq|unknown value in "ploidy" column: "$ploidiness"|;
        }
      }

      $self->_store_annotation($genotype_feature, $cvterm, $pub, $date, $extension,
                               $penetrance, $severity, $long_evidence,
                               $conditions);
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

sub results_summary {
  my $self = shift;
  my $results = shift;

  return '';
}

1;
