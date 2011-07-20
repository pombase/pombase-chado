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

use perl5i::2;
use Moose::Role;

requires 'chado';
requires 'get_cvterm';

method store_feature_rel($subject, $object, $rel_type)
{
  my $rel_cvterm;

  if (ref $rel_type) {
    $rel_cvterm = $rel_type;
  } else {
    $rel_cvterm = $self->get_cvterm('relationship', $rel_type);
  }

  state $ranks = {};

  my $key =
    $subject->feature_id() . '-' . $object->feature_id() . '-' .
    $rel_cvterm->cvterm_id();

  my $rank = 0;

  if (exists $ranks->{$key}) {
    $rank = ++$ranks->{$key};
  } else {
    $ranks->{$key} = 0;
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
