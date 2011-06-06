package PomBase::Role::CvQuery;

=head1 NAME

PomBase::Role::CvQuery - Code for querying the cvterm and cv tables

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::CvQuery

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

method get_cv($cv_name)
{
  return $self->chado()->resultset('Cv::Cv')->find({ name => $cv_name });
}

method get_cvterm($cv_name, $cvterm_name)
{
  my $cv = $self->chado()->resultset('Cv::Cv')->find({ name => $cv_name });

  my $cvterm_rs = $self->chado()->resultset('Cv::Cvterm');
  return $cvterm_rs->find({ name => $cvterm_name,
                            cv_id => $cv->cv_id() });
}

1;
