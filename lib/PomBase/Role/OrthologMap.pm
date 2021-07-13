package PomBase::Role::OrthologMap;

=head1 NAME

PomBase::Role::OrthologMap - Code for querying Chado and returning a hash of 1-1 orthologs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::OrthologMap

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose::Role;

requires 'chado';

sub ortholog_map {
  my $self = shift;

  my $source_organism = shift;
  my $dest_organism = shift;

  my %orthologs = ();

  my $ortholog_rs = $self->chado()->resultset('Sequence::FeatureRelationship')
    ->search(
      {
        'organism.organism_id' => $dest_organism->organism_id(),
        'organism_2.organism_id' => $source_organism->organism_id(),
        'type.name' => 'orthologous_to',
      },
      {
        join => [
          {
            subject => 'organism',
          },
          {
            object => 'organism',
          },
          'type'
        ],
        select => ['subject.uniquename', 'object.uniquename', 'object.name'],
        as => ['subject_uniquename', 'object_uniquename', 'object_name'],
      });

  my %identifier_counts = ();

  while (defined (my $row = $ortholog_rs->next())) {
    my $subject_uniquename = $row->get_column('subject_uniquename');
    my $object_uniquename = $row->get_column('object_uniquename');

    $identifier_counts{$subject_uniquename}++;
    $identifier_counts{$object_uniquename}++;
  }

  $ortholog_rs->reset();

  while (defined (my $row = $ortholog_rs->next())) {
    my $subject_uniquename = $row->get_column('subject_uniquename');
    my $object_uniquename = $row->get_column('object_uniquename');

    if ($identifier_counts{$subject_uniquename} > 1 ||
        $identifier_counts{$object_uniquename} > 1) {
      # skip non one-to-one orthologs
      next;
    }

    my $object_name = $row->get_column('object_name');

    $orthologs{$subject_uniquename} = {
      orth_uniquename => $object_uniquename,
      orth_name => $object_name,
    };
  }

  return %orthologs;
}

sub ortholog_map_reverse {
  my $self = shift;

  my $source_organism = shift;
  my $dest_organism = shift;

  my %ret_map = ();

  my %orthologs = $self->ortholog_map($source_organism, $dest_organism);

  while (my ($subject, $object_details) = each %orthologs) {
    $ret_map{$object_details->{orth_uniquename}} = $subject;
  }

  return %ret_map;
}

1;
