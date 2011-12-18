package PomBase::TestBase;

=head1 NAME

PomBase::TestBase - Moose class that can be used as a base for
                    consuming roles to test

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::TestBase

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2011 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

with 'MooseX::Traits';

has '+_trait_namespace' => ( default => 'PomBase' );

with 'PomBase::Role::ChadoUser';

has verbose => (is => 'ro', isa => 'Bool');

1;
