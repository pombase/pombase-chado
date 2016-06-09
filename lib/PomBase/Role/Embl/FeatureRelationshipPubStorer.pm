package PomBase::Role::Embl::FeatureRelationshipPubStorer;

=head1 NAME

PomBase::Role::Embl::FeatureRelationshipPubStorer - Code for storing rows in the
                           feature_relationship_pub table

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::Embl::FeatureRelationshipPubStorer

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

with 'PomBase::Role::ChadoUser';

method store_feature_rel_pub($feature_rel, $pub) {
  my %create_args = (
    feature_relationship_id => $feature_rel->feature_relationship_id(),
    pub_id => $pub->pub_id(),
  );

  my $featurerel_rs = $self->chado()->resultset('Sequence::FeatureRelationshipPub');

  return $featurerel_rs->create({ %create_args });
}
