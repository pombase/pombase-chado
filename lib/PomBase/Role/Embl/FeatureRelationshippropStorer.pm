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

method store_feature_relationshipprop($feature_relationship, $type_name, $value)
{
  my $type_cvterm = $self->get_cvterm('feature_relationshipprop_type', $type_name);

  if (!defined $type_cvterm) {
    use Carp qw(longmess);
    die "can't find cvterm for $type_name - ", longmess();
  }

  return $self->chado()->resultset('Sequence::FeatureRelationshipprop')
    ->create({ feature_relationship_id =>
                 $feature_relationship->feature_relationship_id(),
               type_id => $type_cvterm->cvterm_id(),
               value => $value,
             });
}
