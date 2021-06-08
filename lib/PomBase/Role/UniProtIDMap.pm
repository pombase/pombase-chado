package PomBase::Role::UniProtIDMap;

=head1 NAME

PomBase::Role::UniProtIDMap - find the local DB ID for a UniProt ID

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::UniProtIDMap

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose::Role;

requires 'chado';
requires 'config';

has uniprot_id_map => (is => 'rw', init_arg => undef,
                       lazy_build => 1);

method _build_uniprot_id_map () {
  my $chado = $self->chado();

  my %id_map = ();

  my $rs = $chado->resultset('Sequence::Featureprop')
    ->search({ 'type.name' => 'uniprot_identifier',
             },
             {
               join => 'type',
               prefetch => {
                 'feature' => 'organism'
               }
             });

#  my $rs = $chado->resultset('Sequence::Featureprop')
#    ->search({ 'type.name' => 'uniprot_identifier' },
#             { join => ['type', { feature => 'type'} ] });

  while (defined (my $prop = $rs->next())) {
    my $feature = $prop->feature();
    my $uniquename = $feature->uniquename();

    my $prefix;

    if ($self->config()->{organism_prefixes}) {
      # this code exists so that pombe genes in JaponicusDB get a "PomBase:"
      # prefix not a "JaponicusDB:" prefix
      my $organism = $feature->organism();
      my $org_full_name = $organism->genus() . '_' . $organism->species();
      $prefix = $self->config()->{organism_prefixes}->{$org_full_name};
    }

    if (!$prefix) {
      $prefix = $self->config()->{database_name};
    }

    $uniquename = "$prefix:$uniquename";

    $id_map{$prop->value()} = $uniquename;
  }

  return \%id_map;
}

sub lookup_uniprot_id {
  my $self = shift;
  my $uniprot_id = shift;

  $uniprot_id =~ s/^UniProtKB://;

  my $local_id = $self->uniprot_id_map()->{$uniprot_id};

  if (defined $local_id) {
    return $local_id;
  } else {
    return undef;
  }
}
