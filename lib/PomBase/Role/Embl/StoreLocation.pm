package PomBase::Role::Embl::StoreLocation;

=head1 NAME

PomBase::Role::Embl::StoreLocation - Code for dealing with Embl feature locations

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::Embl::StoreLocation

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Carp;

use Moose::Role;

requires 'chado';

method store_location($feature, $chromosome, $strand, $start, $end)
{
  my $chado = $self->chado();

  if ($start > $end) {
    ($start, $end) = ($end, $start);
  }

  my %create_args = (
    feature_id => $feature->feature_id(),
    srcfeature_id => $chromosome->feature_id(),
    fmin => $start - 1,
    fmax => $end,
    strand => $strand,
    phase => undef,
    residue_info => undef,
  );

  $self->chado()->resultset('Sequence::Featureloc')->create({ %create_args });
}

1;

