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
use JSON;

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

has json_encoder => (is => 'ro', init_arg => undef, lazy => 1,
                     builder => '_build_json_encoder');

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

sub _build_json_encoder {
  my $self = shift;

  return JSON->new()->pretty(0)->canonical(1);
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
  my $allele_variant = shift;

  my @split_ext_parts = ("");

  if ($extension) {
    @split_ext_parts = sort split /(?<=\))\|/, $extension;
  }

  for my $split_ext (@split_ext_parts) {

    my $feature_cvterm =
      $self->create_feature_cvterm($genotype_feature, $cvterm, $pub, 0);

    # prevent SELECTs later
    $feature_cvterm->feature($genotype_feature);
    $feature_cvterm->cvterm($cvterm);

    $self->add_feature_cvtermprop($feature_cvterm, 'date', $date);

    $self->add_feature_cvtermprop($feature_cvterm, 'annotation_throughput_type',
                                  $self->throughput_type());

    if ($allele_variant) {
      $self->add_feature_cvtermprop($feature_cvterm, 'allele_variant',
                                    $allele_variant);
    }

    my @extension_bits = ();

    if (length $split_ext > 0) {
      push @extension_bits, $split_ext;
    }

    if (length $penetrance > 0) {
      push @extension_bits, "has_penetrance($penetrance)";
    }

    if ($severity =~ /^(\w+)\(([^\)]+)\)$/) {
      my $phenotype_score_type = $1;
      my $phenotype_score = $2;

      $self->add_feature_cvtermprop($feature_cvterm,
                                    annotation_phenotype_score => "$phenotype_score_type($phenotype_score)");

      $severity = '';
    }

    if (length $severity > 0) {
      my $severity_cvterm = $self->find_cvterm_by_term_id($severity);

      if (defined $severity_cvterm) {
        if ($severity_cvterm->cv()->name() ne $fypo_extensions_cv_name) {
          warn "can't load annotation, '$severity' is not from the ",
            "$fypo_extensions_cv_name CV\n";
          return;
        }
      } else {
        warn "can't load annotation, $severity not found\n";
        return;
      }

      push @extension_bits, "has_severity($severity)";
    }

    $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                  $long_evidence);

    my @conditions = split /\s*,\s*/, $conditions;
    my $condition_detail_count = 0;

    for (my $i = 0; $i < @conditions; $i++) {
      my $condition = $conditions[$i];
      my $condition_detail = undef;

      if ($condition =~ /^(\w+:\d+)(?:\((.*)\))/) {
        $condition = $1;
        $condition_detail = $2;
      }

      if (defined $condition_detail) {
        $self->add_feature_cvtermprop($feature_cvterm, 'condition_detail',
                                      "$condition($condition_detail)",
                                      $condition_detail_count);
        $condition_detail_count++;
      }

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

sub _parse_submitter {
  my ($first_value, $submitter_name, $submitter_orcid, $submitter_status) = @_;

  if ($first_value =~ /^#submitter_(\w+):\s*(.*?)\s*$/i) {
    my $type = lc $1;
    my $value = $2;
    if ($type eq 'name') {
      $$submitter_name = $value;
    } else {
      if ($type eq 'orcid') {
        $$submitter_orcid = $value;
      } else {
        if ($type eq 'status') {
          $$submitter_status = $value;
        }
      }
    }
  }
}


sub load {
  my $self = shift;
  my $fh = shift;

  my $file_name = readlink '/proc/self/fd/0';

  if (defined $file_name) {
    $file_name =~ s|.*/||;
  }

  my $chado = $self->chado();
  my $config = $self->config();

  my $csv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  my @col_names = (qw(gene_systemtic_id fypo_id allele_description expression
                        parental_strain strain_background genotype_description
                        gene_name allele_name allele_synonym allele_type
                        evidence conditions penetrance severity extension
                        reference taxon date ploidy allele_variant
                        illegal_extra_column));

  my %stored_alleles = ();

  my %reference_annotation_counts = ();
  my %reference_pub_object = ();

  my $submitter_name = undef;
  my $submitter_orcid = undef;
  my $submitter_status = undef;

  my $columns_ref = {};

  $csv->bind_columns (\@{$columns_ref}{@col_names});

  while ($csv->getline($fh)) {
    my $first_value = trim($columns_ref->{"gene_systemtic_id"});

    if ($first_value =~ /^#/) {
      _parse_submitter($first_value, \$submitter_name, \$submitter_orcid,
                       \$submitter_status);
      next;
    }

    if ($first_value =~ /^Gene[_ ].*(ID|systematic)/i) {
      next;
    }

    my $gene_systemtic_id = $first_value;

    if (length $gene_systemtic_id == 0) {
      warn "no value in the gene_systemtic_id column at line ", $fh->input_line_number(), " - skipping\n";
      next;
    }

    if ($columns_ref->{illegal_extra_column}) {
      warn "too many columns at line ", $fh->input_line_number(),
        " starting with: $columns_ref->{illegal_extra_column}\n";
      next;
    }

    my $fypo_id = trim($columns_ref->{"fypo_id"});
    my $allele_description = $columns_ref->{"allele_description"};
    my $expression = ucfirst $columns_ref->{"expression"};
    my $genotype_description = $columns_ref->{"genotype_description"};
    my $strain_background = $columns_ref->{"strain_background"};
    my $gene_name = $columns_ref->{"gene_name"};
    my $allele_name = $columns_ref->{"allele_name"};
    my $allele_synonyms = $columns_ref->{"allele_synonym"};
    my $allele_type = $columns_ref->{"allele_type"};
    my $evidence = $columns_ref->{"evidence"};
    my $conditions = $columns_ref->{"conditions"};
    my $penetrance = $columns_ref->{"penetrance"};
    my $severity = $columns_ref->{"severity"};
    my $extension = $columns_ref->{"extension"};
    my $reference = trim($columns_ref->{"reference"});
    my $date = $columns_ref->{"date"};
    $date =~ s/^\s*(\d\d\d\d)-?(\d\d)-?(\d\d)\s*$/$1-$2-$3/;

    my $taxonid = $columns_ref->{"taxon"};

    if ($fypo_id eq '') {
      warn qq|FYPO ID missing - skipping line starting with "$gene_systemtic_id"\n|;
      next;
    }

    if (!defined $taxonid) {
      warn "Taxon missing, not enough columns - skipping file\n";
      return;
    }

    $taxonid =~ s/taxon://ig;

    if ($taxonid  !~ /^\d+$/) {
      warn "Taxon is not a number: $taxonid at line ", $fh->input_line_number(), " - skipping\n";
      return;
    }

    my $ploidiness = $columns_ref->{"ploidy"} || "haploid";

    my $allele_variant = $columns_ref->{"allele_variant"};

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

      my $pub = $self->find_or_create_pub($reference);

      $reference_pub_object{$reference} = $pub;

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
          name => $gene_name,
          organism => $organism->genus() . ' ' . $organism->species(),
        },
        name => $allele_name,
        description => $allele_description,
        allele_type => $allele_type,
        pub => $pub,
      };

      $expression = undef if $expression && lc $expression eq 'null';

      my $background_description =
        ($genotype_description // '') . ' ' . ($strain_background // '');

      if ($background_description =~ /^\s*$/) {
        $background_description = undef;
      }

      my $genotype_feature;

      my $allele;

      if ($ploidiness eq 'haploid') {
        ($genotype_feature, $allele) =
          $self->get_genotype_for_allele($background_description, $allele_data, $expression);
      } else {
        if ($ploidiness =~ /^homozygous.diploid$/) {
          $allele = $self->get_allele($allele_data);

          my $genotype_identifier = $self->get_genotype_uniquename();

          my $locus = "$genotype_identifier-$reference-locus-1";
          my @alleles = (
            { allele => $allele, expression => $expression, genotype_locus => $locus },
            { allele => $allele, expression => $expression, genotype_locus => $locus },
          );

          $genotype_feature =
            $self->get_genotype($genotype_identifier, undef,
                                $background_description, undef, \@alleles);

        } else {
          die qq|unknown value in "ploidy" column: "$ploidiness"|;
        }
      }

      if ($allele_synonyms) {
        my @synonyms = map {
          my $synonym = $_;
        } split /\|/, $allele_synonyms;

        $self->store_synonym_if_missing($allele, \@synonyms, $reference);
      }

      $stored_alleles{$allele->feature_id()} = $allele;

      $self->_store_annotation($genotype_feature, $cvterm, $pub, $date, $extension,
                               $penetrance, $severity, $long_evidence,
                               $conditions, $allele_variant);

      $reference_annotation_counts{$reference}++;
    };

    try {
      $chado->txn_do($proc);
    } catch {
      warn "Failed to load line ", $fh->input_line_number(), ": $_\n";
    }
  }

  if (defined $file_name) {
    map {
      my $allele = $_;
      $self->store_featureprop($allele, 'source_file', $file_name);
    } values %stored_alleles;

    if (defined $submitter_name && defined $submitter_orcid &&
        defined $submitter_status) {
      my $encoder = $self->json_encoder();

      while (my ($reference, $count) = each %reference_annotation_counts) {
        my %curator_details = (
          name => $submitter_name,
          orcid => $submitter_orcid,
          annotation_curator => $count,
        );

        if (lc $submitter_status eq 'community') {
          $curator_details{community_curator} = JSON::true;
        } else {
          $curator_details{community_curator} = JSON::false;
        }

        my $curator_json = $encoder->encode(\%curator_details);
        my $pub = $reference_pub_object{$reference};
        $self->create_pubprop($pub, 'annotation_curator', $curator_json);
        warn "$curator_json\n";
      }
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
