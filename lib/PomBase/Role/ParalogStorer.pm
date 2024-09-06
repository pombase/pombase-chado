package PomBase::Role::ParalogStorer;

=head1 NAME

PomBase::Role::OrthologMap - Code for storing paralogs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::ParalogStorer

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

use Moose::Role;

use Try::Tiny;

requires 'chado';

requires 'organism';

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
        'subject.organism_id' => $self->organism()->organism_id(),
        'object.organism_id' => $self->organism()->organism_id(),
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

sub store_paralog_groups
{
  my $self = shift;

  my @groups = @_;

  my $paralogous_to_term = $self->get_cvterm('sequence', 'paralogous_to');

  my %existing_paralogs = $self->existing_paralogs();

  my %created_paralogs = ();

  for my $orth_group (@groups) {
    my $genes = $orth_group->{genes};
    my $date = $orth_group->{date};
    my @gene_ids = @$genes;

    @gene_ids = sort @gene_ids;

    for (my $subj_idx = 0; $subj_idx < @gene_ids-1; $subj_idx++) {
      my $subject_gene_uniquename = $gene_ids[$subj_idx];
      my $subject_gene = undef;
      try {
        $subject_gene = $self->find_chado_feature($subject_gene_uniquename,
                                                  1, 1, $self->organism());
      } catch {
        warn "error calling find_chado_feature(): $_";
      };
      if (!defined $subject_gene) {
        die "can't find: $subject_gene_uniquename\n";
      }

      for (my $obj_idx = $subj_idx+1; $obj_idx < @gene_ids; $obj_idx++) {
        my $object_gene_uniquename = $gene_ids[$obj_idx];
        my $object_gene = undef;
        try {
          $object_gene = $self->find_chado_feature($object_gene_uniquename,
                                                   1, 1, $self->organism());
        }
        catch {
          warn "error calling find_chado_feature(): $_";
        };
        if (!defined $object_gene) {
          die "can't find: $object_gene_uniquename\n";
        }

        my $key = make_key($subject_gene_uniquename, $object_gene_uniquename);

        if (!defined $created_paralogs{$key} && !defined $existing_paralogs{$key}) {
          my $rel = $self->store_feature_rel($subject_gene, $object_gene,
                                             $paralogous_to_term, 1);
          if (defined $date) {
            $self->store_feature_relationshipprop($rel, 'date', $date);
          }

          $created_paralogs{$key} = 1;
        }
      }
    }
  }
}

1;
