package PomBase::Import::GoCamJson;

=head1 NAME

PomBase::Import::GoCamJson - Read the GO-CAM JSON file from SVN in Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::GoCamJson

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2025 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use utf8;

use Moose;
use JSON;
use Getopt::Long qw(GetOptionsFromArray);


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

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has organism => (is => 'rw', init_arg => undef);
has null_pub => (is => 'rw', init_arg => undef);

sub BUILD
{
  my $self = shift;

  my $organism_taxonid = undef;

  my @opt_config = ("organism-taxonid=s" => \$organism_taxonid);

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $organism_taxonid || length $organism_taxonid == 0) {
    die "no --organism-taxonid passed to the importer\n";
  }

  my $organism = $self->find_organism_by_taxonid($organism_taxonid);

  if (!defined $organism) {
    die "can't find organism with taxon ID: $organism_taxonid\n";
  }

  $self->organism($organism);

  my $null_pub = $self->find_or_create_pub('null');

  $self->null_pub($null_pub);
}

sub store_process_terms {
  my $self = shift;
  my $gocam_feature = shift;
  my $title_termids = shift;
  my $process_terms = shift;

  my $chado = $self->chado();

  if (@$title_termids ==  0) {
    warn $gocam_feature->uniquename(), " has no terms in the title " .
      "so won't be attached to any cvterms in Chado\n";
    return;
  }

  my @title_terms = ();

  for my $title_termid (@$title_termids) {
    my $title_term = $self->find_cvterm_by_term_id($title_termid);
    if (defined $title_term) {
      push @title_terms, $title_term;
    } else {
      warn "can't find term $title_termid in title of GO-CAM: ",
          $gocam_feature->uniquename(), "\n";
    }
  }

 PROCESS_TERM:
  for my $process_termid (@$process_terms) {
    my $process_term =
      $self->find_cvterm_by_term_id($process_termid);

    if (!defined $process_term) {
      warn "can't find process term for $process_termid in model: ",
        $gocam_feature->uniquename(), "\n";
      next PROCESS_TERM;
    }

    my $is_title_term_child = 0;

    for my $title_term (@title_terms) {
      my $rs = $self->chado()->resultset('Cv::Cvtermpath')
        ->search({ pathdistance => { '>=' => 0 },
                   subject_id => $process_term->cvterm_id(),
                   'type.name' => { -in => ['is_a', 'part_of'] },
                   object_id => $title_term->cvterm_id(),
                 },
                 {
                   join => 'type',
                 });

      if ($rs->count() > 0) {
        $is_title_term_child = 1;
        last;
      }
    }

    if (!$is_title_term_child) {
      next PROCESS_TERM;
    }

    $self->create_feature_cvterm($gocam_feature, $process_term,
                                 $self->null_pub(), 0);
  }
}

sub store_model_genes {
  my $self = shift;
  my $gocam_feature = shift;
  my $genes = shift;

  my $chado = $self->chado();

  for my $gene_uniquename (@$genes) {
    my $gene_feature =
      $self->find_chado_feature($gene_uniquename, 1, 0,
                                $self->organism(), ['gene']);

    $self->store_feature_rel($gene_feature, $gocam_feature, 'part_of');
  }
}

sub store_modified_genes {
  my $self = shift;
  my $gocam_feature = shift;
  my $modified_gene_pro_terms = shift;

  my $chado = $self->chado();

  for my $pro_termid (@$modified_gene_pro_terms) {
    my $pro_term = $self->find_cvterm_by_term_id($pro_termid);

    if (!defined $pro_term) {
      die "can't find PRO term for $pro_termid\n";
    }

    my $first_prop = $pro_term->cvtermprops()
      ->search({ 'type.name' => 'pombase_gene_id' },
               { join => 'type' })
      ->first();

    if (!defined $first_prop) {
      die "can't find pombase_gene_id property for $pro_termid\n";
    }

    my $pro_term_gene_uniquename = $first_prop->value();

    my $gene_feature =
      $self->find_chado_feature($pro_term_gene_uniquename, 1, 0,
                                $self->organism(), ['gene']);

    $self->store_feature_rel($gene_feature, $gocam_feature, 'part_of');
  }
}

sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $organism = $self->organism();

  my $decoder = JSON->new();

  my $json_text;

  {
    local $/ = undef;
    $json_text = <$fh>;
  }

  my $data = $decoder->decode($json_text);

  while (my ($gocam_id, $details) = each %$data) {
    my $title = $details->{title};
    my $gocam_feature =
      $self->store_feature("$gocam_id", $title, [], 'gocam_model',
                           $organism);

    $self->store_model_genes($gocam_feature, $details->{genes});
    $self->store_modified_genes($gocam_feature, $details->{modified_gene_pro_terms});
    $self->store_process_terms($gocam_feature, $details->{title_terms}, $details->{process_terms});

    if (my $gocam_date = $details->{date}) {
      $self->store_featureprop($gocam_feature, 'gocam_date', $gocam_date);
    }

    for my $gocam_contributor (@{$details->{contributors} // []}) {
      $self->store_featureprop($gocam_feature, 'gocam_contributor',
                               $gocam_contributor);
    }

    for my $title_term (@{$details->{title_terms} // []}) {
      $self->store_featureprop($gocam_feature, 'gocam_title_termid',
                               $title_term);
    }
  }
}

sub results_summary {
  my $self = shift;
  my $results = shift;

  return '';
}

1;
