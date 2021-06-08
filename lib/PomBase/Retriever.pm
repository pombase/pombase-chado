package PomBase::Retriever;

=head1 NAME

PomBase::Retriever - A retriever role

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retriever

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

use Getopt::Long qw(GetOptionsFromArray);

requires qw(config chado find_organism_by_taxonid);

has options => (is => 'ro', isa => 'ArrayRef');
has verbose => (is => 'rw', default => 0);
has organism_taxonid => (is => 'rw');
has organism => (is => 'rw');

sub BUILD {
  my $self = shift;
  my $chado = $self->chado();

  my $organism_taxonid = undef;

  my @opt_config = ("organism-taxon-id=s" => \$organism_taxonid);
  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $organism_taxonid) {
    die "no --organism-taxon-id argument\n";
  }

  $self->organism_taxonid($organism_taxonid);
  $self->organism($self->find_organism_by_taxonid($organism_taxonid));

  die "can't find organism for taxon $organism_taxonid\n"
    unless $self->organism();
}

1;
