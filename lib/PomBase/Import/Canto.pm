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

use perl5i::2;
use Moose;
use charnames ':full';
use Scalar::Util;

use utf8;

use JSON;
use Clone qw(clone);
use Getopt::Long qw(GetOptionsFromArray);

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

# used for checking gene identifiers in "with" parameters
has organism => (is => 'rw', init_arg => undef);

# used to prefix identifiers in "with" fields before storing as proprieties
has db_prefix => (is => 'rw', init_arg => undef);

method _build_extension_processor
{
  my $processor = PomBase::Chado::ExtensionProcessor->new(chado => $self->chado(),
                                                          config => $self->config(),
                                                          pre_init_cache => 1,
                                                          verbose => $self->verbose());
  return $processor;
}

sub BUILD
{
  my $self = shift;

  my $organism_taxonid = undef;
  my $db_prefix = undef;

  my @opt_config = ("organism-taxonid=s" => \$organism_taxonid,
                    "db-prefix=s" => \$db_prefix,
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
}

method _store_interaction_annotation
{
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

my $whitespace_re = "\\s\N{ZERO WIDTH SPACE}";

sub _extensions_by_type
{
  my $extension_text = shift;

  my %by_type = ();

  (my $extension_copy = $extension_text) =~ s/(\([^\)]+\))/_replace_commas($1)/eg;

  $extension_copy =~ s/[^[:ascii:]]//g;

  my @bits = split /,/, $extension_copy;
  for my $bit (@bits) {
    $bit = $bit->trim($whitespace_re);
    $bit = _unreplace_commas($bit);
    if ($bit =~/(.*?)=(.*)/) {
      my $key = $1->trim($whitespace_re);
      my $value = $2->trim($whitespace_re);

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

method _get_real_termid
{
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

method _store_ontology_annotation
{
  my %args = @_;

  my $type = $args{type};
  my $creation_date = $args{creation_date};
  my $termid = $args{termid};
  my $publication = $args{publication};
  my $long_evidence = $args{long_evidence};
  my $feature = $args{feature};
  my $expression = $args{expression};
  my $conditions = $args{conditions};
  my $with_gene = $args{with_gene};
  my $extension_text = $args{extension_text};
  my $extensions = $args{extensions};
  my $curator = $args{curator};
  my $approved_timestamp = $args{approved_timestamp};
  my $approver_email = $args{approver_email};
  my $canto_session = $args{canto_session};
  my $changed_by = $args{changed_by};

  if (defined $extension_text && $extension_text =~ /\|/) {
    die qq(not loading annotation with '|' in extension: "$extension_text"\n);
  }

  my $chado = $self->chado();
  my $config = $self->config();

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

      if ($feature->type()->name() ne 'genotype') {
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
          if ($_->{relation} eq 'residue') {
            push @residues, $_->{rangeValue};
          } else {
            if ($_->{relation} eq 'qualifier') {
              if ($_->{rangeValue} eq 'NOT') {
                $is_not = 1;
              } else {
                push @qualifiers, $_->{rangeValue};
              }
            } else {
              @ret_val = ($_);
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

    my $feature_cvterm =
      $self->create_feature_cvterm($feature, $cvterm, $publication, $is_not);

    $self->add_feature_cvtermprop($feature_cvterm,
                                  assigned_by => $config->{database_name});
    $self->add_feature_cvtermprop($feature_cvterm,
                                  evidence => $long_evidence);
    $self->add_feature_cvtermprop($feature_cvterm,
                                  curator_name => $curator->{name});
    $self->add_feature_cvtermprop($feature_cvterm,
                                  curator_email => $curator->{email});
    $self->add_feature_cvtermprop($feature_cvterm,
                                  community_curated => ($curator->{community_curated} ? 'true' : 'false'));
    $self->add_feature_cvtermprop($feature_cvterm,
                                  canto_session => $canto_session);
    if (defined $approved_timestamp) {
      $self->add_feature_cvtermprop($feature_cvterm,
                                    approved_timestamp => $approved_timestamp);
    }
    if (defined $approver_email) {
      $self->add_feature_cvtermprop($feature_cvterm,
                                    approver_email => $approver_email);
    }
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

        if ($termid !~ /PECO:/) {
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

#        my ($out, $err) = capture {
    $self->extension_processor()->process_one_annotation($feature_cvterm, $annotation_extension, $extensions);
#        };
#        if (length $out > 0) {
#          die $out;
#        }
#        if (length $err > 0) {
#          die $err;
#        }

      my @props_to_store = qw(col17 column_17 residue qualifier condition);

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
                if ($prop_name eq 'column_17' or $prop_name eq 'col17') {
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
method _split_vert_bar($error_prefix, $annotation)
{
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

method _process_feature
{
  my $annotation = clone(shift);
  my $session_metadata = shift;
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
    } qw(approver_email approved_timestamp);

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
      $annotation_type eq 'post_translational_modification') {
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

    if (keys %$annotation > 0) {
      my @keys = keys %$annotation;

      warn "warning in $canto_session: some data from annotation isn't used: @keys\n";
    }

    $self->_store_ontology_annotation(type => $annotation_type,
                                      creation_date => $creation_date,
                                      termid => $termid,
                                      publication => $publication,
                                      long_evidence => $long_evidence,
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
  } else {
    if ($annotation_type eq 'genetic_interaction' or
        $annotation_type eq 'physical_interaction') {
      if (defined $annotation->{interacting_genes}) {
        $self->_store_interaction_annotation(annotation_type => $annotation_type,
                                             creation_date => $creation_date,
                                             interacting_genes => $annotation->{interacting_genes},
                                             publication => $publication,
                                             long_evidence => $long_evidence,
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

method _process_annotation($annotation, $session_genes, $session_genotypes, $session_metadata, $canto_session)
{
  my $status = delete $annotation->{status};

  if ($status eq 'deleted') {
    # this Annotation was created in a session, then deleted
    return;
  }

  if ($status ne 'new') {
    die "unhandled status type: $status\n";
  }

  my $gene_key = delete $annotation->{gene};
  if (defined $gene_key) {
    my $gene = $session_genes->{$gene_key};

    if (!defined $gene) {
      die "internal error: no gene found for $gene_key";
    }

    my $feature;
    if ($annotation->{type} eq 'phenotype' or
        $annotation->{type} eq 'genetic_interaction' or
        $annotation->{type} eq 'physical_interaction') {
      $feature = $gene;
    } else {
      $feature = $self->get_transcript($gene);
    }
    $self->_process_feature($annotation, $session_metadata, $feature,
                            $canto_session, $session_genes);
  }

  my $genotype_key = delete $annotation->{genotype};
  if (defined $genotype_key) {
    my $genotype = $session_genotypes->{$genotype_key};
    $self->_process_feature($annotation, $session_metadata, $genotype,
                            $canto_session, $session_genes);
  }
}

method _query_genes($session_gene_data)
{
  my %ret = ();

  while (my ($key, $details) = each %$session_gene_data) {
    $ret{$key} = $self->get_gene($details);
  }

  return %ret;
}

method _get_alleles($canto_session, $session_genes, $session_allele_data)
{
  my %ret = ();

  for my $key (sort keys %$session_allele_data) {
    my $allele_data = clone $session_allele_data->{$key};
    $allele_data->{canto_session} = $canto_session;
    $allele_data->{gene} = $session_genes->{$allele_data->{gene}};
    my ($out, $err) = capture {
      $ret{$key} = $self->get_allele($allele_data);
    };

    if ($err) {
      $err =~ s/^/warning in $canto_session: /mg;
      warn $err;
    }
  }

  return %ret;
}

method _get_genotypes($session_alleles, $session_genotype_data)
{
  confess "no alleles passed to _get_genotypes()" unless $session_alleles;
  my %ret = ();

  return %ret if !$session_alleles;

  while (my ($genotype_identifier, $details) = each %$session_genotype_data) {
    my @alleles = map {
      my $allele_key = $_->{id};
      {
        expression => $_->{expression},
        allele => $session_alleles->{$allele_key},
      };
    } @{$details->{alleles}};

    $ret{$genotype_identifier} =
      $self->get_genotype($genotype_identifier, $details->{name},
                          $details->{background}, \@alleles);
  }

  return %ret;
}

method load($fh)
{
  my $decoder = JSON->new();

  my $json_text;

  {
    local $/ = undef;
    $json_text = <$fh>;
  }

  my $canto_data = $decoder->decode($json_text);

  my %curation_sessions = %{$canto_data->{curation_sessions}};

  for my $canto_session (keys %curation_sessions) {
    my %session_data = %{$curation_sessions{$canto_session}};

    my %session_genes = $self->_query_genes($session_data{genes});
    my %session_alleles =
      $self->_get_alleles($canto_session, \%session_genes, $session_data{alleles});
    my %session_genotypes =
      $self->_get_genotypes(\%session_alleles, $session_data{genotypes});

    my @annotations = @{$session_data{annotations}};

    my $error_prefix = "warning in $canto_session: ";

    @annotations = map { $self->_split_vert_bar($error_prefix, $_); } @annotations;

    for my $annotation (@annotations) {
      try {
        $self->_process_annotation($annotation, \%session_genes, \%session_genotypes,
                                   $session_data{metadata}, $canto_session);
      } catch {
        (my $message = $_) =~ s/.*txn_do\(\): (.*) at lib.*/$1/;
        chomp $message;
        warn $error_prefix . "$message\n";
      }
    }
  }
}

method results_summary($results)
{
  return '';
}

1;
