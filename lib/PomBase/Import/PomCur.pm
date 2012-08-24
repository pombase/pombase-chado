package PomBase::Import::PomCur;

=head1 NAME

PomBase::Import::PomCur - Load annotation from the community curation
                          tool as JSON format dumps

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::PomCur

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

use JSON;
use Clone qw(clone);

use PomBase::Chado::ExtensionProcessor;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::Embl::FeatureRelationshipPubStorer';
with 'PomBase::Role::Embl::FeatureRelationshippropStorer';
with 'PomBase::Role::InteractionStorer';
with 'PomBase::Role::PhenotypeFeatureFinder';

has verbose => (is => 'ro');
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

method _store_interaction_annotation
{
  my %args = @_;

  my $annotation_type = $args{annotation_type};
  my $creation_date = $args{creation_date};
  my $interacting_genes = $args{interacting_genes};
  my $publication = $args{publication};
  my $long_evidence = $args{long_evidence};
  my $gene_uniquename = $args{gene_uniquename};
  my $curator = $args{submitter_email};
  my $feature_a = $args{feature};
  my $curs_key = $args{curs_key};

  my $organism = $feature_a->organism();

  my $chado = $self->chado();
  my $config = $self->config();

  my $proc = sub {
    for my $feature_b_data (@$interacting_genes) {
      my $feature_b_uniquename = $feature_b_data->{primary_identifier};
      my $feature_b = $self->find_chado_feature($feature_b_uniquename, 1, 1, $organism);
      $self->store_interaction(
        feature_a => $feature_a,
        feature_b => $feature_b,
        rel_type_name => $annotation_type,
        evidence_type => $long_evidence,
        source_db => $config->{db_name_for_cv},
        pub => $publication,
        creation_date => $creation_date,
        curator => $curator,
        curs_key => $curs_key,
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

sub _extensions_by_type
{
  my $extension_text = shift;

  my %by_type = ();

  my $whitespace_re = "\\s\N{ZERO WIDTH SPACE}";

  (my $extension_copy = $extension_text) =~ s/(\([^\)]+\))/_replace_commas($1)/eg;

  $extension_copy =~ s/[^[:ascii:]]//g;

  my @bits = split /,/, $extension_copy;
  for my $bit (@bits) {
    $bit = $bit->trim($whitespace_re);
    $bit = _unreplace_commas($bit);
    if ($bit =~/(.*)=(.*)/) {
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
  my $curator = $args{submitter_email};
  my $approved_timestamp = $args{approved_timestamp};
  my $approver_email = $args{approver_email};
  my $curs_key = $args{curs_key};

  if (defined $extension_text && $extension_text =~ /\|/) {
    warn "not loading annotation with '|' in extension\n";
    return;
  }

  my $chado = $self->chado();
  my $config = $self->config();

  my $proc = sub {
    my $cvterm = $self->find_cvterm_by_term_id($termid);

    if (!defined $cvterm) {
      die "can't load annotation, $termid not found in database\n";
    }

    my $term_name = $cvterm->name();

    my $orig_feature = $feature;
    my $organism = $feature->organism();

    my %by_type = ();

    if (defined $extension_text) {
      %by_type = _extensions_by_type($extension_text);
    }

    my $allele_quals = delete $by_type{allele};

    if (defined $allele_quals && @$allele_quals > 0) {
      my @processed_allele_quals = map {
        my $delete_me = 0;
        if (/^\s*(.*)\((.*)\)/) {
          my $name = $1;
          my $description = $2;

          if ($name eq 'noname' and
              grep /^$description$/, qw(overexpression endogenous knockdown)) {
            if (defined $expression) {
              die "can't have expression=$expression AND allele=$name($description)\n";
            } else {
              $expression = ucfirst $description;
              if (@$allele_quals > 1) {
                $delete_me = 1;
              } else {
                $description = 'unknown';
              }
            }
          }

          if ($delete_me) {
            ();
          } else {
            {
              name => $name,
              description => $description,
              gene => {
                organism => $organism->genus() . ' ' . $organism->species(),
                uniquename => $feature->uniquename(),
              },
              type => 'new',
            }
          }
        } else {
          die qq|allele qualifier "$_" isn't in the form "name(description)"\n|;
        }
      } @$allele_quals;

      if (@processed_allele_quals > 1) {
        die "can't process annotation with two allele qualifiers\n";
      } else {
        $feature = $self->get_allele($processed_allele_quals[0]);
      }
    }

    if ($type =~ /phenotype/) {
      for my $bad_type (qw(qualifier residue)) {
        if (exists $by_type{$bad_type}) {
          die "$type can't have $bad_type=\n";
        }
      }

      if ($feature->type()->name() ne 'allele') {
        die qq(phenotype annotation for "$term_name ($termid)" must have allele information\n);
      }
    }

    my $is_not = 0;

    if (exists $by_type{qualifier}) {
      @{$by_type{qualifier}} = grep {
        if (lc $_ eq 'not') {
          $is_not = 1;
          0;
        } else {
          1;
        }
      } @{$by_type{qualifier}};
    }

    my $feature_cvterm =
      $self->create_feature_cvterm($feature, $cvterm, $publication, $is_not);

    $self->add_feature_cvtermprop($feature_cvterm,
                                  assigned_by => $config->{db_name_for_cv});
    $self->add_feature_cvtermprop($feature_cvterm,
                                  evidence => $long_evidence);
    $self->add_feature_cvtermprop($feature_cvterm,
                                  curator => $curator);
    $self->add_feature_cvtermprop($feature_cvterm,
                                  curs_key => $curs_key);
    if (defined $approved_timestamp) {
      $self->add_feature_cvtermprop($feature_cvterm,
                                    approved_timestamp => $approved_timestamp);
    }
    if (defined $approver_email) {
      $self->add_feature_cvtermprop($feature_cvterm,
                                    approver_email => $approver_email);
    }
    if (defined $with_gene) {
      $self->add_feature_cvtermprop($feature_cvterm, 'with',
                                    $with_gene);
    }
    if (defined $creation_date) {
      $self->add_feature_cvtermprop($feature_cvterm, date => $creation_date);
    }

    if (exists $by_type{expression}) {
      if (defined $expression && $expression ne $by_type{expression}) {
        die "two different expression levels given: $expression and $by_type{expression}\n";
      } else {
        $expression = delete $by_type{expression};
      }
    }

    if (defined $expression) {
      $self->add_feature_cvtermprop($feature_cvterm, expression => $expression);
    }
    if (defined $conditions) {
      for (my $i = 0; $i < @$conditions; $i++) {
        my $termid = $conditions->[$i];
        $self->add_feature_cvtermprop($feature_cvterm, condition => $termid, $i);
      }
    }

    if (keys %by_type > 0) {
      my $annotation_extension_data = delete $by_type{annotation_extension};
      if (defined $annotation_extension_data) {
        my $annotation_extension = join ',', @$annotation_extension_data;
        my ($out, $err) = capture {
        $self->extension_processor()->process_one_annotation($feature_cvterm, $annotation_extension);
        };
        if (length $out > 0) {
          die $out;
        }
        if (length $err > 0) {
          die $err;
        }
      }

      my @props_to_store = qw(col17 residue qualifier condition);

      for my $prop_name (@props_to_store) {
        if (defined (my $prop_vals = delete $by_type{$prop_name})) {
          for (my $i = 0; $i < @$prop_vals; $i++) {
            my $prop_val = $prop_vals->[$i];
            $self->add_feature_cvtermprop($feature_cvterm,
                                          $prop_name, $prop_val, $i);

          }
        }
      }

      for my $type (keys %by_type) {
        die "unhandled type: $type\n";
      }
    }
  };

  $chado->txn_do($proc);
}

# split any annotation with an extension with a vertical bar into multiple
# annotations
method _split_vert_bar($annotation)
{
  my $extension_text = $annotation->{annotation_extension};

  if (defined $extension_text) {
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
  my $curs_key = shift;

  my $annotation_type = delete $annotation->{type};
  my $creation_date = delete $annotation->{creation_date};
  my $publication_uniquename = delete $annotation->{publication};
  my $evidence_code = delete $annotation->{evidence_code};

  my $publication = $self->find_or_create_pub($publication_uniquename);

  my %useful_session_data =
    map {
      ($_, $session_metadata->{$_});
    } qw(submitter_email approver_email approved_timestamp);

  my $long_evidence;

  my $config = $self->config();

  if (!defined $evidence_code or length $evidence_code == 0) {
    die "no evidence code\n";
  } else {
    if (exists $config->{evidence_types}->{$evidence_code}) {
      my $ev_data = $config->{evidence_types}->{$evidence_code};
      if (defined $ev_data) {
        $long_evidence = $ev_data->{name};
      } else {
        $long_evidence = $evidence_code;
      }
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
    my $expression = delete $annotation->{expression};
    my $conditions = delete $annotation->{conditions};

    if (defined delete $annotation->{term_suggestion}) {
      die "annotation with term suggestion not loaded\n";
    }

    if (keys %$annotation > 0) {
      my @keys = keys %$annotation;

      warn "some data from annotation isn't used: @keys\n";
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
                                      curs_key => $curs_key,
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
                                             curs_key => $curs_key,
                                             %useful_session_data);
      } else {
        die "no interacting_genes data found in interaction annotation\n";
      }
    } else {
      warn "can't handle data of type $annotation_type\n";
    }
  }

}

method _process_annotation($annotation, $session_metadata, $curs_key)
{
  my $status = delete $annotation->{status};

  if ($status ne 'new') {
    die "unhandled status type: $status\n";
  }

  my $genes = delete $annotation->{genes};
  if (defined $genes) {
    for my $gene_data (values %$genes) {
      my $feature;
      if ($annotation->{type} eq 'phenotype' or
          $annotation->{type} eq 'genetic_interaction' or
          $annotation->{type} eq 'physical_interaction') {
        $feature = $self->get_gene($gene_data);
      } else {
        $feature = $self->get_transcript($gene_data);
      }
      $self->_process_feature($annotation, $session_metadata, $feature, $curs_key);
    }
  }

  my $alleles = delete $annotation->{alleles};
  if (defined $alleles) {
    for my $allele_data (@$alleles) {
      my $allele = $self->get_allele($allele_data);
      $self->_process_feature($annotation, $session_metadata, $allele, $curs_key);
    }
  }
}

method load($fh)
{
  my $decoder = JSON->new()->utf8();

  my $json_text;

  {
    local $/ = undef;
    $json_text = <$fh>;
  }

  my $pomcur_data = decode_json($json_text);
  my %curation_sessions = %{$pomcur_data->{curation_sessions}};

  for my $curs_key (keys %curation_sessions) {
    my %session_data = %{$curation_sessions{$curs_key}};

    my @annotations = @{$session_data{annotations}};

    my $error_prefix = "error in $curs_key: ";

    @annotations = map { $self->_split_vert_bar($_); } @annotations;

    for my $annotation (@annotations) {
      try {
#        my ($out, $err) = capture {
          $self->_process_annotation($annotation, $session_data{metadata}, $curs_key);
#        };
#        if (length $out > 0) {
#          $out =~ s/^/$error_prefix/mg;
#          warn $out;
#        }
#        if (length $err > 0) {
#          $err =~ s/^/$error_prefix/mg;
#          warn $err;
#        }
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
