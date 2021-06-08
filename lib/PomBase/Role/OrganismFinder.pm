package PomBase::Role::OrganismFinder;

=head1 NAME

PomBase::Role::OrganismFinder - Code for finding organisms in Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::OrganismFinder

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

use feature qw(state);

use Moose::Role;

requires 'chado';
requires 'get_cvterm';

sub find_organism_by_common_name {
  my $self = shift;
  my $common_name = shift;

  return $self->chado()->resultset('Organism::Organism')
    ->find({ common_name => $common_name });
}

sub find_organism_by_full_name {
  my $self = shift;
  my $full_name = shift;

  if (my ($genus, $species) = $full_name =~ /^\s*(\S+)\s+(.*?)\s*$/) {
    return $self->chado()->resultset('Organism::Organism')
      ->find({ genus => $genus, species => $species });
  } else {
    croak 'argument to find_organism_by_full_name() needs to be "Genus species"';
  }
}

sub find_organism_by_taxonid {
  my $self = shift;
  my $taxonid = shift;

  state $cache = {};

  if (exists $cache->{$taxonid}) {
    return $cache->{$taxonid};
  }

  my $taxonid_term = $self->get_cvterm('organism property types', 'taxon_id');
  my $organism_rs = $self->chado()->resultset('Organism::Organismprop')
    ->search({ type_id => $taxonid_term->cvterm_id(), value => $taxonid })
    ->search_related('organism');

  my $organism = $organism_rs->next();

  if (defined $organism_rs->next()) {
    die "more than one organism for taxon: $taxonid";
  }

  $cache->{$taxonid} = $organism;

  return $organism;
}

1;
