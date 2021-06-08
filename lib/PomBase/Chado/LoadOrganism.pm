package PomBase::Chado::LoadOrganism;

=head1 NAME

PomBase::Chado::LoadOrganism - Load organisms into Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::LoadOrganism

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

use Moose;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';

has verbose => (is => 'ro');

sub load_organism {
  my $self = shift;
  my $genus = shift;
  my $species = shift;
  my $common_name = shift;
  my $abbreviation = shift;
  my $taxon_id = shift;

  my $taxon_id_cvterm =
    $self->find_cvterm_by_name('organism property types', 'taxon_id');

  my $organism =
    $self->chado()->resultset('Organism::Organism')->create({
      genus => $genus,
      species => $species,
      common_name => $common_name,
      abbreviation => $abbreviation,
      organismprops =>
        [ { value => $taxon_id,
            type_id => $taxon_id_cvterm->cvterm_id() } ] });
}

1;
