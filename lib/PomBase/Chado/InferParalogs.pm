package PomBase::Chado::InferParalogs;

=head1 NAME

PomBase::Chado::InferParalogs - Infer paralogs using orthologs

=head1 DESCRIPTION

Infer paralogs from orthologs.  Create paralog annotations for
all genes that share a common ortholog.

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::InferParalogs

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2024 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Try::Tiny;

use Moose;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::OrthologMap';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has this_taxonid => (is => 'rw', init_arg => undef);
has ortholog_taxonid => (is => 'rw', init_arg => undef);

has this_organism => (is => 'rw', init_arg => undef);
has ortholog_organism => (is => 'rw', init_arg => undef);

sub BUILD
{
  my $self = shift;

  my $this_taxonid = undef;
  my $ortholog_taxonid = undef;

  my @opt_config = ("this-taxonid=s" => \$this_taxonid,
                    "ortholog-taxonid=s" => \$ortholog_taxonid,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $this_taxonid || length $this_taxonid == 0) {
    die "no --this-taxonid passed to the InferParalogs processor\n";
  }

  my $this_organism = $self->find_organism_by_taxonid($this_taxonid);
  $self->this_organism($this_organism);

  if (!defined $ortholog_taxonid || length $ortholog_taxonid == 0) {
    die "no --ortholog-taxonid passed to the InferParalogs processor\n";
  }

  my $ortholog_organism = $self->find_organism_by_taxonid($ortholog_taxonid);
  $self->ortholog_organism($ortholog_organism);
}

sub make_key
{
  my $object_gene_uniquename = shift;
  my $subject_gene_uniquename = shift;

  return "$subject_gene_uniquename<->$object_gene_uniquename";
}

sub existing_paralogs
{
  my $self = shift;

  my %paralogs = ();

  my $rs = $self->chado()->resultset('Sequence::FeatureRelationship')
    ->search(
      {
        'subject.organism_id' => $self->this_organism()->organism_id(),
        'object.organism_id' => $self->this_organism()->organism_id(),
        'type.name' => 'paralogous_to',
      },
      {
        join => [ 'subject', 'type', 'object' ],
      }
    );

  while (defined (my $para = $rs->next())) {
    my $subject = $para->subject();
    my $object = $para->object();
    $paralogs{make_key($subject->uniquename(), $object->uniquename())} = 1;
    $paralogs{make_key($object->uniquename(), $subject->uniquename())} = 1;
  }

  return %paralogs;
}

sub process
{
  my $self = shift;

  my %ortholog_map =
    $self->ortholog_map($self->this_organism(), $self->ortholog_organism());

  my $paralogous_to_term = $self->get_cvterm('sequence', 'paralogous_to');

  my %existing_paralogs = $self->existing_paralogs();

  my %created_paralogs = ();

  for my $orth_groups (values %ortholog_map) {
    my @orth_groups = @$orth_groups;

    next if @orth_groups == 1;

    @orth_groups = sort @orth_groups;

    for (my $subj_idx = 0; $subj_idx < @orth_groups-1; $subj_idx++) {
      my $subject_gene_uniquename = $orth_groups[$subj_idx];
      my $subject_gene = undef;
      try {
        $subject_gene = $self->find_chado_feature($subject_gene_uniquename,
                                                  1, 1, $self->this_organism());
      } catch {
        warn "error calling find_chado_feature(): $_";
      };
      if (!defined $subject_gene) {
        die "can't find: $subject_gene_uniquename\n";
      }

      for (my $obj_idx = $subj_idx+1; $obj_idx < @orth_groups; $obj_idx++) {
        my $object_gene_uniquename = $orth_groups[$obj_idx];
        my $object_gene = undef;
        try {
          $object_gene = $self->find_chado_feature($object_gene_uniquename,
                                                   1, 1, $self->this_organism());
        }
        catch {
          warn "error calling find_chado_feature(): $_";
        };
        if (!defined $object_gene) {
          die "can't find: $object_gene_uniquename\n";
        }

        my $key = make_key($subject_gene_uniquename, $object_gene_uniquename);

        if (!defined $created_paralogs{$key} && !defined $existing_paralogs{$key}) {
          print "create $subject_gene_uniquename $object_gene_uniquename\n";
          $self->store_feature_rel($subject_gene, $object_gene,
                                   $paralogous_to_term, 1);

          $created_paralogs{$key} = 1;
        }
      }
    }
  }
}

1;
