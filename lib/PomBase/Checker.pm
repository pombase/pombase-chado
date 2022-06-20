package PomBase::Checker;

=head1 NAME

PomBase::Check - Base class for database checking

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Check

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

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';

has website_config => (is => 'ro');
has check_config => (is => 'ro');
has output_text => (is => 'rw');

requires 'description';


1;
