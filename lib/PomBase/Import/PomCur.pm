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

has verbose => (is => 'ro');
has extension_processor => (is => 'ro', init_arg => undef, lazy => 1,
                            builder => '_build_extension_processor');

method _build_extension_processor
{
  my $processor = PomBase::Chado::ExtensionProcessor->new(chado => $self->chado(),
                                                          config => $self->config(),
                                                          pre_init_cache => 1);
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
      );
    }
  };

  $chado->txn_do($proc);
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

    my $orig_feature = $feature;

    my %by_type = ();

    if (defined $extension_text) {
      my @bits = split /,/, $extension_text;
      for my $bit (@bits) {
        if ($bit =~/(.*)=(.*)/) {
          my $key = $1->trim("\\s\N{ZERO WIDTH SPACE}");
          my $value = $2->trim("\\s\N{ZERO WIDTH SPACE}");
          push @{$by_type{$key}}, $value;
        }
      }
    }

    my $allele_qual = delete $by_type{allele};

    if (defined $allele_qual && length $allele_qual > 0 ) {
      if ($allele_qual =~ /^\s*(.*)\((.*)\)/) {
        my $organism = $feature->organism();
        my %allele_data = (
          name => $1,
          description => $2,
          gene => {
            organism => $organism->genus() . ' ' . $organism->species(),
            uniquename => $feature->uniquename(),
          },
          type => 'new',
        );
        $feature = $self->_get_allele(\%allele_data);
      } else {
        die qq|allele qualifier "$allele_qual" isn't in the form "name(description)"|;
      }
    }

    my $feature_cvterm =
      $self->create_feature_cvterm($feature, $cvterm, $publication, 0);

    $self->add_feature_cvtermprop($feature_cvterm,
                                  assigned_by => $config->{db_name_for_cv});
    $self->add_feature_cvtermprop($feature_cvterm,
                                  evidence => $long_evidence);
    $self->add_feature_cvtermprop($feature_cvterm,
                                  curator => $curator);
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
    if (defined $expression) {
      $self->add_feature_cvtermprop($feature_cvterm, expression => $expression);
    }
    if (defined $conditions) {
      map {
        my $termid = $_;
        $self->add_feature_cvtermprop($feature_cvterm, condition => $termid);
      } @$conditions;
    }

    if (keys %by_type > 0) {
      my $annotation_extension_data = delete $by_type{annotation_extension};
      if (defined $annotation_extension_data) {
        my $annotation_extension = join ',', @$annotation_extension_data;
        $self->extension_processor()->process_one_annotation($feature_cvterm, $annotation_extension);
      }

      my @props_to_store = qw(residue qualifier condition);

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
        warn "unhandled type: $type\n";
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
                                             %useful_session_data);
      } else {
        die "no interacting_genes data found in interaction annotation\n";
      }
    } else {
      warn "can't handle data of type $annotation_type\n";
    }
  }

}

method _get_gene($gene_data)
{
  my $gene_uniquename = $gene_data->{uniquename};
  my $organism_name = $gene_data->{organism};
  my $organism = $self->find_organism_by_full_name($organism_name);

  return $self->find_chado_feature($gene_uniquename, 1, 1, $organism);
}

method _get_transcript($gene_data)
{
  my $gene_uniquename = $gene_data->{uniquename};
  my $organism_name = $gene_data->{organism};
  my $organism = $self->find_organism_by_full_name($organism_name);

  return $self->find_chado_feature("$gene_uniquename.1", 1, 1, $organism);
}

method _get_allele($allele_data)
{
  my $allele;
  my $gene = $self->_get_gene($allele_data->{gene});
  if ($allele_data->{type} eq 'existing') {
    $allele = $self->chado()->resultset('Sequence::Feature')
                   ->find({ uniquename => $allele_data->{primary_identifier},
                            organism_id => $gene->organism()->organism_id() });
    if (!defined $allele) {
      use Data::Dumper;
      die "failed to create allele from: ", Dumper([$allele_data]);
    }
  } else {
    my $allele_cvterm = $self->get_cvterm('sequence', 'allele');
    my $organism_id = $gene->organism()->organism_id();
    my $gene_uniquename = $gene->uniquename();

    my $new_name = $self->get_new_uniquename($gene_uniquename . ':allele-', 1);
    $allele = $self->chado()->resultset('Sequence::Feature')
                   ->create({ uniquename => $new_name,
                              name => $allele_data->{name},
                              organism_id => $organism_id,
                              type_id =>$allele_cvterm->cvterm_id() });
    $self->store_feature_rel($allele, $gene, 'instance_of');

    if (defined $allele_data->{description}) {
      $self->store_featureprop($allele, 'description', $allele_data->{description});
    }
  }

  return $allele;
}

method _process_annotation($annotation, $session_metadata)
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
        $feature = $self->_get_gene($gene_data);
      } else {
        $feature = $self->_get_transcript($gene_data);
      }
      $self->_process_feature($annotation, $session_metadata, $feature)
    }
  }

  my $alleles = delete $annotation->{alleles};
  if (defined $alleles) {
    for my $allele_data (@$alleles) {
      my $allele = $self->_get_allele($allele_data);
      $self->_process_feature($annotation, $session_metadata, $allele)
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
          $self->_process_annotation($annotation, $session_data{metadata});
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

1;
