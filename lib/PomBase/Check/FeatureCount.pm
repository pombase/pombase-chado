package PomBase::Check::FeatureCount;

=head1 NAME

PomBase::Check::FeatureCount - Check that there are enough genes

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Check::FeatureCount

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

method description() {
  return "Check that there are enough genes";
}

with 'PomBase::Checker';

method check() {
  my $min_count = $self->config()->{ref $self}->{min_count};
  # this should really look at each organism,
  $self->chado()->resultset("Sequence::Feature")->count() > $min_count;
}

1;
