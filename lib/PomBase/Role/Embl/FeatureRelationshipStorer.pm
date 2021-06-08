package PomBase::Role::Embl::FeatureRelationshipStorer;

=head1 NAME

PomBase::Role::Embl::FeatureRelationshipStorer - Code for storing relationships

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::Embl::FeatureRelationshipStorer

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose::Role;

requires 'chado';
requires 'get_cvterm';

has ranks => (is => 'ro',
              lazy => 1, builder => '_build_ranks');

# preinitialise the hash of ranks of the existing feature_relationships
sub _build_ranks {
  my $self = shift;

  my $chado = $self->chado();

  my $rs = $chado->resultset('Sequence::FeatureRelationship');

  my $ranks = {};

  while (defined (my $rel = $rs->next())) {
    my $key = $rel->subject_id() . '-' . $rel->object_id() . '-' . $rel->type_id();
    my $rank = $rel->rank();
    if (exists $ranks->{$key}) {
      if ($rank > $ranks->{$key}) {
        $ranks->{$key} = $rank;
      } else {
        next;
      }
    } else {
      $ranks->{$key} = $rank;
    }
  }

  return $ranks;
}



sub store_feature_rel {
  my $self = shift;
  my $subject = shift;
  my $object = shift;
  my $rel_type = shift;
  my $no_duplicates = shift;
  my $rank_arg = shift;

  my $rel_cvterm;

  if (ref $rel_type) {
    $rel_cvterm = $rel_type;
  } else {
    $rel_cvterm = $self->get_relation_cvterm($rel_type);
  }

  if (!defined $subject) {
    croak "subject undefined in store_feature_rel()";
  }

  if (!defined $object) {
    croak "object undefined in store_feature_rel()";
  }

  if (!defined $rel_cvterm) {
    croak "no cvterm found for $rel_type in store_feature_rel()";
  }

  if ($self->verbose()) {
    warn "  storing feature_relationship with type ", $rel_cvterm->name(),
      " subject: ", $subject->uniquename(), " to object: ",
      $object->uniquename(), "\n";
  }

  my $key =
    $subject->feature_id() . '-' . $object->feature_id() . '-' .
    $rel_cvterm->cvterm_id();

  my $rank = 0;

  if (defined $rank_arg) {
    $rank = $rank_arg;
  } else {
    if (!$no_duplicates) {
      if (exists $self->ranks()->{$key}) {
        $rank = ++$self->ranks()->{$key};
      } else {
        $self->ranks()->{$key} = 0;
      }
    }
  }

  my %create_args = (
    type_id => $rel_cvterm->cvterm_id(),
    object_id => $object->feature_id(),
    subject_id => $subject->feature_id(),
    rank => $rank,
  );

  my $featurerel_rs = $self->chado()->resultset('Sequence::FeatureRelationship');

  return $featurerel_rs->create({ %create_args });
}

1;
