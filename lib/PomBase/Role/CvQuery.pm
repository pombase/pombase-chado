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
  state $cache = {};

  return $cache->{$cv_name} //
         ($cache->{$cv_name} =
           $self->chado()->resultset('Cv::Cv')->find({ name => $cv_name }));
}

method get_cvterm($cv_name, $cvterm_name)
{
  my $cv = $self->get_cv($cv_name);

  state $cache = {};

  if (exists $cache->{$cv_name}->{$cvterm_name}) {
    return $cache->{$cv_name}->{$cvterm_name};
  }

  my $cvterm_rs = $self->chado()->resultset('Cv::Cvterm');
  my $cvterm = $cvterm_rs->find({ name => $cvterm_name,
                                  cv_id => $cv->cv_id() });

  $cache->{$cv_name}->{$cvterm_name} = $cvterm;

  return $cvterm;
}

1;
