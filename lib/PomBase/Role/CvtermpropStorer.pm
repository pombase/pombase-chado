package PomBase::Role::CvtermpropStorer;

=head1 NAME

PomBase::Role::CvtermpropStorer - Code for storing rows in cvtermprop

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::CvtermpropStorer

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

requires 'get_cvterm';
requires 'chado';

method store_cvtermprop($cvterm, $type_name, $value)
{
  my $type_cvterm = $self->get_cvterm('cvterm_property_type', $type_name);

  if (!defined $type_cvterm) {
    die "can't find cvterm for $type_name\n";
  }

  $self->chado->resultset('Cv::Cvtermprop')->create({
    cvterm_id => $cvterm->cvterm_id(),
    type_id => $type_cvterm->cvterm_id(),
    value => $value,
  });
}

1;
