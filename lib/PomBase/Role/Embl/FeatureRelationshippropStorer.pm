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

use perl5i::2;
use Moose::Role;

requires 'chado';
requires 'get_cvterm';

has ranks => (is => 'ro', lazy_build => 1);

sub _make_key
{
  my $feature_relationship_id = shift;
  my $type_id = shift;

  return "$feature_relationship_id-$type_id";
}

# preinitialise the hash of ranks of the existing feature_relationshipprop
method _build_ranks() {
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

method store_feature_relationshipprop($feature_relationship, $type_name, $value) {
  my $type_cvterm =
    $self->find_or_create_cvterm('feature_relationshipprop_type', $type_name);

  if (!defined $type_cvterm) {
    use Carp qw(longmess);
    die "can't find cvterm for $type_name - ", longmess();
  }

  if (ref $value) {
    croak "can't store a reference as a value";
  }

  my $key = _make_key($feature_relationship->feature_relationship_id(),
                      $type_cvterm->cvterm_id());

  my $rank = 0;

  if (exists $self->ranks()->{$key}) {
    $rank = ++$self->ranks()->{$key};
  } else {
    $self->ranks()->{$key} = 0;
  }

  return $self->chado()->resultset('Sequence::FeatureRelationshipprop')
    ->create({ feature_relationship_id =>
                 $feature_relationship->feature_relationship_id(),
               type_id => $type_cvterm->cvterm_id(),
               value => $value,
               rank => $rank,
             });
}
