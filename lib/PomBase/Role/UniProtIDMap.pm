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

use perl5i::2;
use Moose::Role;

requires 'chado';

has uniprot_id_map => (is => 'rw', init_arg => undef,
                       lazy_build => 1);

method _build_uniprot_id_map () {
  my $chado = $self->chado();

  my %id_map = ();

  my $rs = $chado->resultset('Sequence::Featureprop')
    ->search({ 'type.name' => 'uniprot_identifier' },
             { join => ['type', { feature => 'type' } ] });

  while (defined (my $prop = $rs->next())) {
    $id_map{$prop->value()} = $prop->feature()->uniquename();
  }

  return \%id_map;
}

method lookup_uniprot_id($uniprot_id) {
  $uniprot_id =~ s/^UniProtKB://;

  my $local_id = $self->uniprot_id_map()->{$uniprot_id};

  if (defined $local_id) {
    return $local_id;
  } else {
    return undef;
  }
}
