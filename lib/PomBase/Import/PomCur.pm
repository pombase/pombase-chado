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

use JSON;

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

has verbose => (is => 'ro');
has extension_processor => (is => 'ro', init_arg => undef, lazy => 1,
                            builder => '_build_extension_processor');

method _build_extension_processor
{
  my $processor = PomBase::Chado::ExtensionProcessor->new(chado => $self->chado(),
                                                          config => $self->config());
  return $processor;
}

method _store_ontology_annotation
{
  my %args = @_;

  my $type = $args{type};
  my $creation_date = $args{creation_date};
  my $termid = $args{termid};
  my $publication_uniquename = $args{publication_uniquename};
  my $evidence_code = $args{evidence_code};
  my $gene_uniquename = $args{gene_uniquename};
  my $organism_name = $args{organism_name};
  my $with_gene = $args{with_gene};
  my $annotation_extension = $args{annotation_extension};

  my $chado = $self->chado();
  my $config = $self->config();

  my $long_evidence =
    $config->{evidence_types}->{$evidence_code}->{name};

  if (!defined $long_evidence) {
    die "unknown evidence code: $evidence_code\n";
  }

  my $organism = $self->find_organism_by_full_name($organism_name);

  my $transcript_name = "$gene_uniquename.1";
  my $feature = $self->find_chado_feature($transcript_name, 1, 1, $organism);

  my $proc = sub {
    my $pub = $self->find_or_create_pub($publication_uniquename);

    my $cvterm = $self->find_cvterm_by_term_id($termid);

    if (!defined $cvterm) {
      die "can't load annotation, $termid not found in database\n";
    }

    my $feature_cvterm =
      $self->create_feature_cvterm($feature, $cvterm, $pub, 0);

    $self->add_feature_cvtermprop($feature_cvterm, 'assigned_by',
                                  $config->{db_name_for_cv});
    $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                  $long_evidence);
    if (defined $with_gene) {
      $self->add_feature_cvtermprop($feature_cvterm, 'with',
                                    $with_gene);
    }

    if (defined $annotation_extension) {
      $self->extension_processor()->process_one_annotation($feature_cvterm, $annotation_extension);
    }
  };

  $chado->txn_do($proc);
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

    my %genes = %{$session_data{genes}};

    for my $gene_tag (keys %genes) {
      my %gene_data = %{$genes{$gene_tag}};

      next unless exists $gene_data{annotations};

      my $organism_name = $gene_data{organism};
      my $gene_uniquename = $gene_data{uniquename};

      my @annotations = @{$gene_data{annotations}};

      for my $annotation (@annotations) {
        my $annotation_type = delete $annotation->{type};
        my $creation_date = delete $annotation->{creation_date};
        my $publication_uniquename = delete $annotation->{publication};

        if ($annotation_type eq 'biological_process' or
            $annotation_type eq 'molecular_function' or
            $annotation_type eq 'cellular_component' or
            $annotation_type eq  'fission_yeast_phenotype') {
          my $termid = delete $annotation->{term};
          my $evidence_code = delete $annotation->{evidence_code};
          my $status = delete $annotation->{status};

          if ($status ne 'new') {
            die "unhandled status type: $status\n";
          }

          my $with_gene = delete $annotation->{with_gene};

          my $annotation_extension = delete $annotation->{annotation_extension};

          if (keys %$annotation > 0) {
            my @keys = keys %$annotation;

            die "some data from annotation isn't used: @keys\n";
          }

          $self->_store_ontology_annotation(type => $annotation_type,
                                            creation_date => $creation_date,
                                            termid => $termid,
                                            publication_uniquename =>
                                              $publication_uniquename,
                                            evidence_code => $evidence_code,
                                            gene_uniquename =>
                                              $gene_uniquename,
                                            organism_name => $organism_name,
                                            with_gene => $with_gene,
                                            annotation_extension =>
                                              $annotation_extension);
        } else {
          warn "can't handle data of type $annotation_type\n";
        }
      }
    }
  }
}

1;
