package PomBase::Import::Canto;

=head1 NAME

PomBase::Import::Canto - Load annotation from the community curation
                         tool as JSON format dumps

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Canto

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2011 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use feature qw(state);

use Try::Tiny;
use Capture::Tiny qw(capture);

use Moose;
use charnames ':full';
use Scalar::Util;

use utf8;

use JSON;
use Clone qw(clone);
use Getopt::Long qw(GetOptionsFromArray);

use PomBase::Chado::ExtensionProcessor;

use PomBase::Chado::GenotypeCache;

has genotype_cache => (is => 'ro', required => 1,
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
with 'PomBase::Role::FeatureRelationshipFinder';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::Embl::FeatureRelationshipPubStorer';
with 'PomBase::Role::Embl::FeatureRelationshippropStorer';
with 'PomBase::Role::InteractionStorer';
with 'PomBase::Role::LegacyAlleleHandler';
with 'PomBase::Role::PhenotypeFeatureFinder';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);
has extension_processor => (is => 'ro', init_arg => undef, lazy => 1,
                            builder => '_build_extension_processor');
has json_encoder => (is => 'ro', init_arg => undef, lazy => 1,
                     builder => '_build_json_encoder');

# used for checking gene identifiers in "with" parameters
has organism => (is => 'rw', init_arg => undef);

# used to prefix identifiers in "with" fields before storing as proprieties
has db_prefix => (is => 'rw', init_arg => undef);

has all_curation_is_community => (is => 'rw', init_arg => undef);

has seen_binding_annotations => (is => 'rw', init_arg => undef, default => sub { {} });
has possible_reciprocal_binding_annotations => (is => 'rw', init_arg => undef, default => sub { [] });

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

sub BUILD
{
  my $self = shift;

  my $organism_taxonid = undef;
  my $db_prefix = undef;
  my $all_curation_is_community = 0;

  my @opt_config = ("organism-taxonid=s" => \$organism_taxonid,
                    "db-prefix=s" => \$db_prefix,
                    "all-curation-is-community" => \$all_curation_is_community,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $organism_taxonid || length $organism_taxonid == 0) {
    die "no --organism-taxonid passed to the Canto loader\n";
  }

  my $organism = $self->find_organism_by_taxonid($organism_taxonid);

  if (!defined $organism) {
    die "can't find organism with taxon ID: $organism_taxonid\n";
  }

  $self->organism($organism);

  if (!defined $db_prefix) {
    die "no --db-prefix passed to the Canto loader\n";
  }

  $self->db_prefix($db_prefix);

  $self->all_curation_is_community($all_curation_is_community);
}

sub _store_interaction_annotation {
  my $self = shift;
  my %args = @_;

  my $annotation_type = $args{annotation_type};
  my $creation_date = $args{creation_date};
  my $interacting_genes = $args{interacting_genes};
  my $publication = $args{publication};
  my $long_evidence = $args{long_evidence};
  my $gene_uniquename = $args{gene_uniquename};
  my $curator = $args{curator};
  my $feature_a = $args{feature};
  my $canto_session = $args{canto_session};
  my $session_genes = $args{session_genes};
  my $annotation_throughput_type = $args{annotation_throughput_type};

  my $organism = $feature_a->organism();

  my $chado = $self->chado();
  my $config = $self->config();

  my $proc = sub {
    for my $feature_b_key (@$interacting_genes) {
      my $feature_b = $session_genes->{$feature_b_key};
      # this will store the reciprocal annotation for symmetrical interactions
      $self->store_interaction(
        feature_a => $feature_a,
        feature_b => $feature_b,
        rel_type_name => $annotation_type,
        evidence_type => $long_evidence,
        annotation_throughput_type => $annotation_throughput_type,
        source_db => $config->{database_name},
        pub => $publication,
        creation_date => $creation_date,
        curator => $curator,
        canto_session => $canto_session,
      );
    }
  };

  $chado->txn_do($proc);
}

my $comma_substitute = "<<COMMA>>";

sub _replace_commas
{
  my $string = shift;

  $string =~ s/,/$comma_substitute/g;
  return $string;
}

sub _unreplace_commas
{
  my $string = shift;

  $string =~ s/$comma_substitute/,/g;
  return $string;
}

my $whitespace_re = qr([\s\N{ZERO WIDTH SPACE}]+);

sub _extensions_by_type
{
  my $extension_text = shift;

  my %by_type = ();

  (my $extension_copy = $extension_text) =~ s/(\([^\)]+\))/_replace_commas($1)/eg;

  $extension_copy =~ s/[^[:ascii:]]//g;

  my @bits = split /,/, $extension_copy;
  for my $bit (@bits) {
    $bit =~ s/^$whitespace_re|$whitespace_re$//g;
    $bit = _unreplace_commas($bit);
    if ($bit =~/(.*?)=(.*)/) {
      my $key = $1;
      $key =~ s/^$whitespace_re|$whitespace_re$//g;
      my $value = $2;
      $value =~ s/^$whitespace_re|$whitespace_re$//g;

      if ($value =~ /\(/ && $value !~ /\(.*\)/) {
        die "unmatched parenthesis in $key=$value\n";
      }

      push @{$by_type{$key}}, $value;
    } else {
      push @{$by_type{annotation_extension}}, $bit;
    }
  }

  return %by_type;
}

sub _get_real_termid {
  my $self = shift;
  my $termid = shift;

  my $cvterm = $self->find_cvterm_by_term_id($termid);

  if (!defined $cvterm) {
    die "can't load condition, $termid not found in database\n";
  }

  if ($cvterm->is_obsolete()) {
    die "condition '$termid' is obsolete\n";
  }

  my $dbxref = $cvterm->dbxref();
  my $real_termid = $dbxref->db()->name() . ':' . $dbxref->accession();

  return $real_termid;
}

sub _make_binding_key {
  my $gene_uniquename = shift;
  my $with_uniquename = shift;
  my $termid = shift;
  my $pub_uniquename = shift;
  my $extensions = shift;

  my $ext_string = join '-::-',
    map {
      $_->{relation} . '(' . $_->{rangeValue} . ')'
    } @$extensions;
  return join '-:-',
    ($gene_uniquename, $with_uniquename, $termid, $pub_uniquename, $ext_string);
}

sub _store_ontology_annotation {
  my $self = shift;
  my %args = @_;

  my $type = $args{type};
  my $creation_date = $args{creation_date};
  my $termid = $args{termid};
  my $publication = $args{publication};
  my $long_evidence = $args{long_evidence};
  my $gene = $args{gene};
  my $feature = $args{feature};
  if (!defined $feature) {
    die "no feature passed to _store_ontology_annotation()\n";
  }
  my $expression = $args{expression};
  my $conditions = $args{conditions};
  my $with_gene = $args{with_gene};
  my $extension_text = $args{extension_text};
  my $extensions = $args{extensions};
  my $curator = $args{curator};
  my $canto_session = $args{canto_session};
  my $changed_by = $args{changed_by};

  if ($with_gene && $termid eq 'GO:0005515') {
    my $feature_uniquename = undef;
    if (defined $gene) {
      # $feature is a transcript but we need to use the gene uniquename to make the key
      $feature_uniquename = $gene->uniquename();
    } else {
      $feature_uniquename = $feature->uniquename();
    }

    my $seen_key = _make_binding_key($feature_uniquename, $with_gene,
                                     $termid, $publication->uniquename(),
                                     $extensions // []);

    $self->seen_binding_annotations()->{$seen_key} = 1;
  }

  if (defined $extension_text && $extension_text =~ /\|/) {
    die qq(not loading annotation with '|' in extension: "$extension_text"\n);
  }

  my $chado = $self->chado();
  my $config = $self->config();

  my $transcript_isoform_id = undef;

  if ($extensions) {
    my @filtered_extensions = ();

    map {
      if ($_->{relation} eq 'transcript_isoform_id') {
        if (defined $transcript_isoform_id) {
          die "more than one transcript_isoform_id extension for ", $feature->uniquename(), "\n";
        } else {
          $transcript_isoform_id = $_->{rangeValue};
        }
      } else {
        push @filtered_extensions, $_;
      }

    } @$extensions;

    @$extensions = @filtered_extensions;
  }

  if ($transcript_isoform_id) {
    my $database_name = $config->{database_name};

    $transcript_isoform_id =~ s/^$database_name://;

    if ($transcript_isoform_id =~ /:/) {
      die qq|badly formatted transcript_isoform_id ID: "$transcript_isoform_id"\n|;
    }

    if ($transcript_isoform_id ne $feature->uniquename()) {
      # annotation is not for this transcript
      return;
    }
  }

  my $warning_prefix = "warning in $canto_session: ";

  # nested transaction
  $chado->txn_begin();

  try {
    my $cvterm = $self->find_cvterm_by_term_id($termid);

    if (!defined $cvterm) {
      my $obsolete_cvterm = $self->find_cvterm_by_term_id($termid, { include_obsolete => 1 });
      if (defined $obsolete_cvterm) {
        die "can't load annotation, $termid is an obsolete term\n";
      } else {
        die "can't load annotation, $termid not found in database\n";
      }
    }

    my $term_name = $cvterm->name();

    my $orig_feature = $feature;

    my %by_type = ();

    if (defined $extension_text) {
      %by_type = _extensions_by_type($extension_text);
    }

    my $allele_type = undef;

    my $allele_quals = delete $by_type{allele};

    if (defined $allele_quals && @$allele_quals > 0) {
      if (@$allele_quals > 1) {
        die "more than one allele specified\n";
      }
      my @processed_allele_quals = map {
        my $res = $self->make_allele_data_from_display_name($feature, $_, \$expression);

        $res->{canto_session} = $canto_session;

        my $allele_type_list = delete $by_type{allele_type};

        if ($allele_type_list) {
          # use allele type from the extension text
          $allele_type = $allele_type_list->[0];
          $res->{allele_type} = $allele_type;
        }

        $res;
      } @$allele_quals;

      if (@processed_allele_quals == 0) {
        die "can't find allele data\n";
      }

      if (@processed_allele_quals > 1) {
        die "can't process annotation with two allele qualifiers\n";
      } else {
        $feature = $self->get_genotype_for_allele($processed_allele_quals[0], $expression);
      }
    }

    if ($type =~ /phenotype/) {
      for my $bad_type (qw(qualifier residue)) {
        if (exists $by_type{$bad_type}) {
          die "$type can't have $bad_type=\n";
        }
      }

      if ($feature->type()->name() ne 'genotype' and $feature->type()->name() ne 'genotype_interaction') {
        die qq|phenotype annotation for "$term_name ($termid)" must have genotype information | .
          "has " . $feature->type()->name() . " instead\n";
      }
    }

    my $is_not = 0;

    my @residues = ();
    my @qualifiers = ();
    my @column_17_values = ();

    if ($extensions) {
      @$extensions =
        map {
          my @ret_val = ();
          my $range_value = $_->{rangeValue};
          if ($_->{relation} eq 'residue') {
            push @residues, $range_value;
          } else {
            if ($_->{relation} =~ /^col(?:umn)?(?:_)?17|modified_form$/) {
              push @column_17_values, $range_value;
            } else {
              if ($_->{relation} eq 'has_qualifier') {
                if ($range_value eq 'NOT' || $range_value eq 'PBHQ:002') {
                  $is_not = 1;
                } else {
                  if ($range_value =~ /^(\w+):(\d+)$/) {
                    my $range_value_term = $self->find_cvterm_by_term_id($range_value);
                    push @qualifiers, $range_value_term->name();
                  } else {
                    push @qualifiers, $range_value;
                  }
                }
              } else {
                @ret_val = ($_);
              }
            }
          }
          @ret_val;
        } @$extensions;
    }

    if (exists $by_type{qualifier}) {
      # don't override the NOT from the extensions
      if (!$is_not) {
        @{$by_type{qualifier}} = grep {
          if (lc $_ eq 'not') {
            $is_not = 1;
            0;
          } else {
            1;
          }
        } @{$by_type{qualifier}};
      }
    }

    my $all_curation_is_community = $self->all_curation_is_community();

    my $community_curated_flag;

    if ($curator->{community_curated} || $all_curation_is_community) {
      $community_curated_flag = 'true';
    } else {
      $community_curated_flag = 'false';
    }

    my $feature_cvterm =
      $self->create_feature_cvterm($feature, $cvterm, $publication, $is_not);

    $self->add_feature_cvtermprop($feature_cvterm, 'annotation_throughput_type',
                                  'low throughput');
    $self->add_feature_cvtermprop($feature_cvterm,
                                  assigned_by => $config->{database_name});
    $self->add_feature_cvtermprop($feature_cvterm,
                                  evidence => $long_evidence);
    $self->add_feature_cvtermprop($feature_cvterm,
                                  curator_name => $curator->{name});
    $self->add_feature_cvtermprop($feature_cvterm,
                                  community_curated => $community_curated_flag);
    $self->add_feature_cvtermprop($feature_cvterm,
                                  canto_session => $canto_session);
    if (defined $changed_by) {
      $self->add_feature_cvtermprop($feature_cvterm,
                                    changed_by => $changed_by);
    }
    if (defined $with_gene) {
      try {
        my $ref_feature =
          $self->find_chado_feature($with_gene, 1, 1, $self->organism());
        $with_gene = $ref_feature->uniquename();
      } catch {
        warn $warning_prefix, "can't find feature using identifier: $with_gene\n";
      };

      my $db_prefix = $self->db_prefix();

      $self->add_feature_cvtermprop($feature_cvterm, 'with',
                                    "$db_prefix:$with_gene");
    }
    if (defined $creation_date) {
      $self->add_feature_cvtermprop($feature_cvterm, date => $creation_date);
    }

    if (exists $by_type{expression}) {
      my @expressions = @{delete $by_type{expression}};

      if (@expressions > 1) {
        die "more than one expression given: @expressions\n";
      }

      my $ext_expression = $expressions[0];

      if (defined $expression && $expression ne $ext_expression) {
        die "two different expression levels given: $expression and $ext_expression\n";
      }
      $expression = ucfirst $ext_expression;
    }

    if (defined $conditions) {
      for (my $i = 0; $i < @$conditions; $i++) {
        my $termid = $conditions->[$i];

        if ($termid !~ /FYECO:/) {
          die "condition '$termid' isn't a PECO term ID\n";
        }

        my $real_termid = $self->_get_real_termid($termid);

        $self->add_feature_cvtermprop($feature_cvterm, condition => $real_termid, $i);
      }
    }

    my $annotation_extension_data = delete $by_type{annotation_extension};

    my $annotation_extension;

    if (defined $annotation_extension_data) {
      $annotation_extension = join ',', @$annotation_extension_data;
    } else{
      $annotation_extension = '';
    }

    my ($out, $err) = capture {
      $self->extension_processor()->process_one_annotation($feature_cvterm, $annotation_extension, $extensions);
    };
    if (length $out > 0) {
      die $out;
    }
    if (length $err > 0) {
      die $err;
    }

    my @props_to_store = qw(col17 column_17 modified_form residue qualifier condition);

    for my $prop_name (@props_to_store) {
      if (defined (my $prop_vals = delete $by_type{$prop_name})) {
        for (my $i = 0; $i < @$prop_vals; $i++) {
          my $prop_val = $prop_vals->[$i];

          if ($prop_name eq 'residue') {
            push @residues, $prop_val;
          } else {
            if ($prop_name eq 'qualifier') {
              push @qualifiers, $prop_val;
            } else {
              if ($prop_name eq 'column_17' or $prop_name eq 'col17' or
                  $prop_name eq 'modified_form') {
                push @column_17_values, $prop_val;
              } else {
                if ($prop_name eq 'condition') {
                  $prop_val = $self->_get_real_termid($prop_val);
                }

                $self->add_feature_cvtermprop($feature_cvterm,
                                              $prop_name, $prop_val, $i);
              }
            }
          }
        }
      }
    }

    for (my $i = 0; $i < @residues; $i++) {
      my $residue = $residues[$i];
      $self->add_feature_cvtermprop($feature_cvterm, residue => $residue, $i);
    }

    for (my $i = 0; $i < @qualifiers; $i++) {
      my $qualifier = $qualifiers[$i];
      $self->add_feature_cvtermprop($feature_cvterm, qualifier => $qualifier, $i);
    }

    for (my $i = 0; $i < @column_17_values; $i++) {
      my $col_17_value = $column_17_values[$i];
      $self->add_feature_cvtermprop($feature_cvterm,
                                    'gene_product_form_id' => $col_17_value, $i);
    }

    $chado->txn_commit();
  } catch {
    $chado->txn_rollback();
    chomp (my $message = $_);
    warn $warning_prefix, "$message\n";
  }
}

# split any annotation with an extension with a vertical bar into multiple
# annotations
sub _split_vert_bar {
  my $self = shift;
  my $error_prefix = shift;
  my $annotation = shift;

  my $extension_text = $annotation->{annotation_extension};

  if (defined $extension_text) {
    if ($extension_text =~ /\|\s*$/) {
      warn $error_prefix . qq(trailing "|" in annotation_extension: "$extension_text"\n);
      $extension_text =~ s/\|\s*$//;

      $annotation->{annotation_extension} = $extension_text;
    }

    my @ex_bits = split /\|/, $extension_text;

    if (@ex_bits > 1) {
      return map { my $new_annotation = clone $annotation;
                   $new_annotation->{annotation_extension} = $_;
                   $new_annotation; } @ex_bits;
    } else {
      return $annotation;
    }
  } else {
    return $annotation;
  }
}

sub _process_feature {
  my $self = shift;
  my $annotation = clone(shift);
  my $session_metadata = shift;
  my $gene = shift;     # undef unless $feature is a transcript
  my $feature = shift;
  my $canto_session = shift;
  my $session_genes = shift;

  my $annotation_type = delete $annotation->{type};
  my $creation_date = delete $annotation->{creation_date};
  my $publication_uniquename = delete $annotation->{publication};
  my $evidence_code = delete $annotation->{evidence_code};
  my $curator = delete $annotation->{curator};
  my $changed_by = delete $annotation->{changed_by};

  my $changed_by_json = undef;

  if (defined $changed_by) {
    my $encoder = JSON->new()->utf8()->pretty(0)->canonical(1);
    $changed_by_json = $encoder->encode($changed_by);
  }

  my $publication = $self->find_or_create_pub($publication_uniquename);

  my %useful_session_data =
    map {
      ($_, $session_metadata->{$_});
    } qw(first_approved_timestamp approved_timestamp);

  my $long_evidence;

  my $config = $self->config();

  if (!defined $evidence_code or length $evidence_code == 0) {
    die "no evidence code for $annotation_type\n";
  } else {
    if (exists $config->{evidence_types}->{lc $evidence_code}) {
      my $ev_data = $config->{evidence_types}->{lc $evidence_code};
      $long_evidence = $ev_data->{name};
    } else {
      die "unknown evidence code: $evidence_code\n";
    }
  }

  if ($annotation_type eq 'biological_process' or
      $annotation_type eq 'molecular_function' or
      $annotation_type eq 'cellular_component' or
      $annotation_type eq 'phenotype' or
      $annotation_type eq 'post_translational_modification' or
      $annotation_type eq 'wt_rna_expression' or
      $annotation_type eq 'wt_protein_expression' or
      $annotation_type eq 'protein_sequence_feature_or_motif') {
    my $termid = delete $annotation->{term};
    my $with_gene = delete $annotation->{with_gene};
    my $extension_text = delete $annotation->{annotation_extension};
    my $extensions = delete $annotation->{extension};
    my $expression = delete $annotation->{expression};
    my $conditions = delete $annotation->{conditions};

    my $term_suggestion = delete $annotation->{term_suggestion};
    if (defined $term_suggestion &&
        ($term_suggestion->{name} || $term_suggestion->{definition})) {
      die "annotation with term suggestion not loaded\n";
    }

    delete $annotation->{submitter_comment};
    delete $annotation->{checked};

    if (keys %$annotation > 0) {
      my @keys =
        grep {
          $_ ne 'organism' and $_ ne 'figure' and $_ ne 'old_term_ontid' and
          $_ ne 'genotype_interactions_with_phenotype' and
          $_ ne 'genotype_interactions_no_phenotype';
        } keys %$annotation;

      if (@keys) {
        warn "warning in $canto_session: some data from annotation isn't used: @keys\n";
      }
    }

    $self->_store_ontology_annotation(type => $annotation_type,
                                      creation_date => $creation_date,
                                      termid => $termid,
                                      publication => $publication,
                                      long_evidence => $long_evidence,
                                      gene => $gene,
                                      feature => $feature,
                                      expression => $expression,
                                      conditions => $conditions,
                                      with_gene => $with_gene,
                                      extension_text => $extension_text,
                                      extensions => $extensions,
                                      canto_session => $canto_session,
                                      curator => $curator,
                                      changed_by => $changed_by_json,
                                      %useful_session_data);

    if ($with_gene && $evidence_code eq 'IPI' && $termid eq 'GO:0005515' &&
        $feature->type()->name() eq 'mRNA') {
      # create a reciprocal annotation that will be stored later if a matching
      # manual annotation isn't seen

      my $with_gene_key =
        $feature->organism->genus() . ' ' . $feature->organism->species() . ' ' . $with_gene;
      my $with_feature = $session_genes->{$with_gene_key};

      my $with_feature_transcript = ($self->get_transcripts_of_gene($with_feature))[0];

      if (!defined $with_feature) {
        die "internal error: no gene found for $with_feature";
      }

      # keep only "during" extensions
      my @reciprocal_extensions =
        grep {
          $_->{relation} =~ /during/;
        } @{$extensions || []};

      my %reciprocal_details = (
        type => $annotation_type,
        creation_date => $creation_date,
        termid => $termid,
        publication => $publication,
        long_evidence => $long_evidence,
        gene => $with_feature,
        feature => $with_feature_transcript,
        expression => $expression,
        conditions => $conditions,
        with_gene => $gene->uniquename(),
        extension_text => undef,
        extensions => \@reciprocal_extensions,
        canto_session => $canto_session,
        curator => $curator,
        changed_by => $changed_by_json,
        %useful_session_data
      );

      push @{$self->possible_reciprocal_binding_annotations()}, \%reciprocal_details;
    }
  } else {
    if ($annotation_type eq 'genetic_interaction' or
        $annotation_type eq 'physical_interaction') {
      if (defined $annotation->{interacting_genes}) {
        $self->_store_interaction_annotation(annotation_type => $annotation_type,
                                             creation_date => $creation_date,
                                             interacting_genes => $annotation->{interacting_genes},
                                             publication => $publication,
                                             long_evidence => $long_evidence,
                                             annotation_throughput_type => 'low throughput',
                                             feature => $feature,
                                             canto_session => $canto_session,
                                             curator => $curator,
                                             changed_by => $changed_by_json,
                                             session_genes => $session_genes,
                                             %useful_session_data);
      } else {
        die "no interacting_genes data found in interaction annotation\n";
      }
    } else {
      warn "can't handle data of type $annotation_type\n";
    }
  }

}

sub _process_interactions {
  my $self = shift;

  my $annotation = shift;
  my $session_genotypes = shift;
  my $session_metadata = shift;

  my $pub_uniquename = $session_metadata->{curation_pub_id};
  my $pub = $self->find_or_create_pub($pub_uniquename);

  my $curs_key = $session_metadata->{canto_session};

  state $uniquename_counts = {};

  my @return_interactions = ();

  my @interaction_data = ();

  if (exists $annotation->{genotype_interactions_no_phenotype}) {
    @interaction_data = @{$annotation->{genotype_interactions_no_phenotype}};
  }

  if (exists $annotation->{genotype_interactions_with_phenotype}) {
    push @interaction_data, @{$annotation->{genotype_interactions_with_phenotype}};
  }

  for my $interaction_data (@interaction_data) {
    my $genotype_a_uniquename = $interaction_data->{genotype_a};
    my $genotype_a = $session_genotypes->{$genotype_a_uniquename};
    my $genotype_b_uniquename = $interaction_data->{genotype_b};
    my $genotype_b = $session_genotypes->{$genotype_b_uniquename};
    my $interaction_type = $interaction_data->{interaction_type};

    my $interaction_identifier =
      $genotype_a_uniquename =~ s/$curs_key-genotype-//r .
      '-' .
      $genotype_b_uniquename =~ s/$curs_key-genotype-//r;

    my $count_suffix = $uniquename_counts->{$interaction_identifier}++;

    $interaction_identifier =
      $curs_key . '-interaction-' . $interaction_identifier . '-' . $count_suffix;

    my $interaction_feature =
      $self->store_feature($interaction_identifier,
                           undef, [], 'genotype_interaction',
                           $self->organism());

    $self->store_featureprop($interaction_feature, 'interaction_type',
                             $interaction_type);

    if ($interaction_data->{genotype_a_phenotype_termid}) {
      $self->store_featureprop($interaction_feature, 'interaction_rescued_phenotype_id',
                               $interaction_data->{genotype_a_phenotype_termid});
    }

    my $rel_a = $self->store_feature_rel($genotype_a, $interaction_feature,
                                         'interaction_genotype_a');
    my $rel_b = $self->store_feature_rel($genotype_b, $interaction_feature,
                                         'interaction_genotype_b');

    $self->create_feature_pub($interaction_feature, $pub);

    push @return_interactions, $interaction_feature;
  }

  return @return_interactions;
}

sub _process_annotation {
  my $self = shift;
  my $annotation = shift;
  my $session_genes = shift;
  my $session_genotypes = shift;
  my $session_metadata = shift;
  my $canto_session = shift;

  my $status = delete $annotation->{status};

  if ($status eq 'deleted') {
    # this Annotation was created in a session, then deleted
    return;
  }

  if ($status ne 'new') {
    die "unhandled status type: $status\n";
  }

  my @new_interactions =
    $self->_process_interactions($annotation, $session_genotypes,
                                 $session_metadata);

  my $gene_key = delete $annotation->{gene};
  if (defined $gene_key) {
    my $gene = $session_genes->{$gene_key};

    if (!defined $gene) {
      die "internal error: no gene found for $gene_key";
    }

    my @features;
    if ($annotation->{type} eq 'phenotype' or
        $annotation->{type} eq 'genetic_interaction' or
        $annotation->{type} eq 'physical_interaction') {
      push @features, $gene;
    } else {
      @features = $self->get_transcripts_of_gene($gene);
    }
    map {
      my $feature = $_;
      $self->_process_feature($annotation, $session_metadata, $gene, $feature,
                              $canto_session, $session_genes);
    } @features;
  }

  my $genotype_key = delete $annotation->{genotype};
  if (defined $genotype_key) {
    my $genotype = $session_genotypes->{$genotype_key};
    if (defined $genotype_key) {
      $self->_process_feature($annotation, $session_metadata, undef, $genotype,
                              $canto_session, $session_genes);
    } else {
      warn "can't store annotation for missing genotype: $genotype_key\n";
    }
  }

  for my $interaction (@new_interactions) {
    $self->_process_feature($annotation, $session_metadata, undef,
                            $interaction,
                            $canto_session, $session_genes);
  }
}

sub _query_genes {
  my $self = shift;
  my $session_gene_data = shift;

  my %ret = ();

  while (my ($key, $details) = each %$session_gene_data) {
    $ret{$key} = $self->get_gene($details);
  }

  return %ret;
}

sub _get_alleles {
  my $self = shift;
  my $pubmed_id = shift;
  my $canto_session = shift;
  my $session_genes = shift;
  my $session_allele_data = shift;

  my %ret = ();

  for my $key (sort keys %$session_allele_data) {
    my $allele_data = clone $session_allele_data->{$key};
    $allele_data->{canto_session} = $canto_session;
    $allele_data->{gene} = $session_genes->{$allele_data->{gene}};
    my ($out, $err) = capture {
      my $allele = $self->get_allele($allele_data);
      $ret{$key} = $allele;
      if ($allele_data->{synonyms}) {
        my $chado = $self->chado();

        my @existing_synonyms = $chado->resultset('Sequence::FeatureSynonym')
          ->search({ feature_id => $allele->feature_id() },
                   { prefetch => 'synonym' })->all();

        my @existing_names = map {
          $_->synonym()->name();
        } @existing_synonyms;

        for my $new_synonym (@{$allele_data->{synonyms}}) {
          if (!grep { $_ eq $new_synonym } @existing_names) {
            $self->store_feature_synonym($allele, $new_synonym, 'exact', 1,
                                         $pubmed_id);
          }
        }
      }
    };

    if ($err) {
      $err =~ s/^/warning in $canto_session: /mg;
      warn $err;
    }
  }

  return %ret;
}

sub _get_genotypes {
  my $self = shift;
  my $canto_session = shift;
  my $session_alleles = shift;
  my $session_genotype_data = shift;

  confess "no alleles passed to _get_genotypes()" unless $session_alleles;
  my %ret = ();

  return %ret if !$session_alleles;

  while (my ($genotype_identifier, $details) = each %$session_genotype_data) {
    my @loci = @{$details->{loci}};
    my @alleles = ();

    for (my $locus_index = 0; $locus_index < @loci; $locus_index++) {
      my $locus = $loci[$locus_index];
      map {
        my $allele_key = $_->{id};
        my $expressed_allele = {
          expression => $_->{expression},
          allele => $session_alleles->{$allele_key},
        };
        $expressed_allele->{genotype_locus} =
          "$genotype_identifier-locus-" . ($locus_index+1);
        push @alleles, $expressed_allele;
      } @{$locus};
    }

    if (@alleles) {
      my $new_genotype =
        $self->get_genotype($genotype_identifier, $details->{name},
                            $details->{background}, $details->{comment}, \@alleles);

      $ret{$genotype_identifier} = $new_genotype;

      $self->store_featureprop($new_genotype, 'canto_session',
                               $canto_session);

    } else {
      warn "genotype $genotype_identifier has no alleles\n";
    }
  }

  return %ret;
}

sub _store_metadata {
  my $self = shift;
  my $metadata = shift;

  my $encoder = $self->json_encoder();

  my $chado = $self->chado();

  my $pub_uniquename = $metadata->{curation_pub_id};
  my $pub = $self->find_or_create_pub($pub_uniquename);

  $self->create_pubprop($pub, 'canto_session', $metadata->{canto_session});
  if ($metadata->{first_approved_timestamp}) {
    $self->create_pubprop($pub, 'canto_first_approved_date', $metadata->{first_approved_timestamp});
  }
  if ($metadata->{first_sent_to_curator_date}) {
    $self->create_pubprop($pub, 'canto_first_sent_to_curator_date',
                          $metadata->{first_sent_to_curator_date});
  }
  if ($metadata->{approved_timestamp}) {
    $self->create_pubprop($pub, 'canto_approved_date', $metadata->{approved_timestamp});
  }
  if ($metadata->{annotation_status}) {
    $self->create_pubprop($pub, 'canto_annotation_status', $metadata->{annotation_status});
  }
  if ($metadata->{approver_name}) {
    $self->create_pubprop($pub, 'canto_approver_name', $metadata->{approver_name});
  }
  if ($metadata->{initial_curator_name}) {
    $self->create_pubprop($pub, 'canto_initial_curator_name', $metadata->{initial_curator_name});
  }
  if ($metadata->{curator_name}) {
    $self->create_pubprop($pub, 'canto_curator_name', $metadata->{curator_name});
  }
  if ($metadata->{previous_curators}) {
    map {
      my $prev_curator = $_;
      $self->create_pubprop($pub, 'previous_curator_name', $prev_curator->{curator_name});
    } @{$metadata->{previous_curators}}
  }
  if ($metadata->{curator_role}) {
    my $curator_role = $metadata->{curator_role};
    if ($self->all_curation_is_community()) {
      $curator_role = "community";
    }

    $self->create_pubprop($pub, 'canto_curator_role', $curator_role);
  }
  if ($metadata->{curation_accepted_date}) {
    $self->create_pubprop($pub, 'canto_session_accepted_date', $metadata->{curation_accepted_date});
  }
  if ($metadata->{needs_approval_timestamp}) {
    $self->create_pubprop($pub, 'canto_session_submitted_date', $metadata->{needs_approval_timestamp});
  }
  if ($metadata->{message_for_curators}) {
    $self->create_pubprop($pub, 'canto_message_for_curators', $metadata->{message_for_curators});
  }
  if ($metadata->{annotation_curators}) {
    for my $annotation_curator (@{$metadata->{annotation_curators}}) {
      my $annotation_curator_json = $encoder->encode($annotation_curator);
      $self->create_pubprop($pub, 'annotation_curator', $annotation_curator_json);
    }
  }
}

sub _process_publications {
  my $self = shift;
  my $publications = shift;

  for my $pub_uniquename (keys %$publications) {
    my $data = $publications->{$pub_uniquename};

    my $pub = $self->find_or_create_pub($pub_uniquename);

    $self->create_pubprop($pub, 'canto_triage_status', $data->{triage_status});
    if ($data->{added_date}) {
      $self->create_pubprop($pub, 'canto_added_date', $data->{added_date});
    }
  }
}

sub _process_sessions {
  my $self = shift;
  my $curation_sessions = shift;

  for my $canto_session (keys %$curation_sessions) {
    my %session_data = %{$curation_sessions->{$canto_session}};

    my $metadata = $session_data{metadata};
    $self->_store_metadata($metadata);

    my %session_genes = $self->_query_genes($session_data{genes});
    my %session_alleles =
      $self->_get_alleles($metadata->{curation_pub_id}, $canto_session,
                          \%session_genes, $session_data{alleles});
    my %session_genotypes =
      $self->_get_genotypes($canto_session,
                            \%session_alleles, $session_data{genotypes});

    if (defined $session_data{annotations}) {
      my @annotations = @{$session_data{annotations}};

      my $error_prefix = "warning in $canto_session: ";

      @annotations = map { $self->_split_vert_bar($error_prefix, $_); } @annotations;

      for my $annotation (@annotations) {
        try {
          $self->_process_annotation($annotation, \%session_genes, \%session_genotypes,
                                     $metadata, $canto_session);
        } catch {
          (my $message = $_) =~ s/.*txn_do\(\): (.*) at lib.*/$1/;
          chomp $message;
          warn $error_prefix . "$message\n";
        }
      }
    }

    for my $possible_annotation (@{$self->possible_reciprocal_binding_annotations()}) {

      my $feature_uniquename;

      if ($possible_annotation->{gene}) {
        $feature_uniquename = $possible_annotation->{gene}->uniquename()
      } else {
        $feature_uniquename = $possible_annotation->{feature}->uniquename()
      }

      my $key = _make_binding_key($feature_uniquename,
                                  $possible_annotation->{with_gene},
                                  $possible_annotation->{termid},
                                  $possible_annotation->{publication}->uniquename(),
                                  $possible_annotation->{extensions} // []);

      if (!$self->seen_binding_annotations()->{$key}) {
        $self->_store_ontology_annotation(%$possible_annotation);
      }
    }

    # reset for next session:
    $self->seen_binding_annotations({});
    $self->possible_reciprocal_binding_annotations([]);
  }
}

sub load {
  my $self = shift;
  my $fh = shift;

  my $decoder = JSON->new();

  my $json_text;

  {
    local $/ = undef;
    $json_text = <$fh>;
  }

  my $canto_data = $decoder->decode($json_text);

  my $publications = $canto_data->{publications};

  if ($publications) {
    $self->_process_publications($publications);
  }

  my %curation_sessions = %{$canto_data->{curation_sessions}};

  $self->_process_sessions(\%curation_sessions);
}

sub results_summary {
  my $self = shift;
  my $results = shift;

  return '';
}

1;
