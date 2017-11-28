package PomBase::Import::Organisms;

=head1 NAME

PomBase::Import::Organisms - load organisms and taxon IDs from a tab
                             separated file

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Organisms

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

with 'PomBase::Role::ChadoUser';

use PomBase::Chado::LoadOrganism;

has verbose => (is => 'ro');

method load($fh) {
  my $org_load = PomBase::Chado::LoadOrganism->new(chado => $self->chado);

  while(<$fh>) {
    next if /^#/;
    chomp $_;
    my ($genus, $species, $common_name, $abbreviation, $taxon_id) = split /\t/, $_;
    $org_load->load_organism($genus, $species, $common_name, $abbreviation, $taxon_id);
  }
}

1;
