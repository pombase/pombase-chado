package PomBase::Role::CoordCalculator;

=head1 NAME

PomBase::Role::CoordCalculator - Code for getting exon locations from features

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::CoordCalculator

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

method coords_of_feature($feature)
{
  carp "undefined feature passed to _coords_of_feature()" unless $feature;
  my $loc = $feature->location();
  return map { [$_->start(), $_->end()]; } $loc->each_Location();
}



1;
