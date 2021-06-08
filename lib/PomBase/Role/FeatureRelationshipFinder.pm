package PomBase::Role::FeatureRelationshipFinder;

=head1 NAME

PomBase::Role::FeatureRelationshipFinder - Role to finding feature_relationship
                                           rows

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::FeatureRelationshipFinder

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

=head2 get_feature_relationship

 Usage   : my $rel = $self->get_feature_relationship($feat1, $feat2, $pub, $evidence);
 Function: Find a feature_relationship
 Args    : $feat1     - a Sequence::Feature (bait)
           $feat2     - a Sequence::Feature (bait)
           $pub       - a publication (Pub) object
           $evidence  - a code like "Synthetic Lethality"
 Return  : the FeatureRelationship

=cut

sub get_feature_relationship {
  my $self = shift;
  my $feature_1 = shift;
  my $feature_2 = shift;
  my $pub = shift;
  my $evidence = shift;

  my $chado = $self->chado();

  my $rs = $chado->resultset('Sequence::FeatureRelationship')
    ->search(
      {
        'subject.feature_id' => $feature_1->feature_id(),
        'object.feature_id' => $feature_2->feature_id(),
        'type.name' => 'evidence',
        'feature_relationshipprops.value' => $evidence,
        'pub.pub_id' => $pub->pub_id,
      },
      {
        join => ['subject', 'object',
                 { feature_relationshipprops => 'type' },
                 { feature_relationship_pubs => 'pub' }],
      });

  return $rs->all();
}

1;
