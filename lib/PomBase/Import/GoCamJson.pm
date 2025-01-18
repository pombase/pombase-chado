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
  my $process_terms = shift;

  my $chado = $self->chado();

  for my $process_term_id (@$process_terms) {
    my $process_term =
      $self->find_cvterm_by_term_id($process_term_id);

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
    $self->store_process_terms($gocam_feature, $details->{process_terms});

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
