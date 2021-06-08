package PomBase::Role::Embl::FeatureRelationshippropStorer;

=head1 NAME

PomBase::Role::Embl::FeatureRelationshippropStorer - Store properties of
        feature_relationships

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::Embl::FeatureRelationshippropStorer

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

has feature_rel_prop_ranks => (is => 'ro', lazy_build => 1);

sub _make_key
{
  my $feature_relationship_id = shift;
  my $type_id = shift;

  return "$feature_relationship_id-$type_id";
}

# preinitialise the hash of ranks of the existing feature_relationshipprop
sub _build_feature_rel_prop_ranks {
  my $self = shift;

  my $chado = $self->chado();

  my $rs = $chado->resultset('Sequence::FeatureRelationshipprop');

  my $ranks = {};

  while (defined (my $prop = $rs->next())) {
    my $key = _make_key($prop->feature_relationship_id(), $prop->type_id());
    my $rank = $prop->rank();
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

sub store_feature_relationshipprop {
  my $self = shift;
  my $feature_relationship = shift;
  my $type_name = shift;
  my $value = shift;

  my $type_cvterm =
    $self->find_or_create_cvterm('feature_relationshipprop_type', $type_name);

  if (!defined $type_cvterm) {
    use Carp qw(longmess);
    die "can't find cvterm for $type_name - ", longmess();
  }

  if (!defined $value) {
    die "undef value in store_feature_relationshipprop(",
      $feature_relationship->feature_relationship_id(), ", $type_name, undef)";
  }

  if (ref $value) {
    croak "can't store a reference as a value";
  }

  my $key = _make_key($feature_relationship->feature_relationship_id(),
                      $type_cvterm->cvterm_id());

  my $rank = 0;

  if (exists $self->feature_rel_prop_ranks()->{$key}) {
    $rank = ++$self->feature_rel_prop_ranks()->{$key};
  } else {
    $self->feature_rel_prop_ranks()->{$key} = 0;
  }

  return $self->chado()->resultset('Sequence::FeatureRelationshipprop')
    ->create({ feature_relationship_id =>
                 $feature_relationship->feature_relationship_id(),
               type_id => $type_cvterm->cvterm_id(),
               value => $value,
               rank => $rank,
             });
}

1;
