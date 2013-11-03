package PomBase::Chado;

=head1 NAME

PomBase::Chado - Code for accessing the Pombe Chado database

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado

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

use Bio::Chado::Schema;

=head2 db_connect

 Usage   : PomBase::Chado::connect($database, $username, $password)
 Function: Connect to a PomBase Chado database and return a DBIx::Class schema
           object
 Args    : $database - the name of the database
 Returns : a Bio::Chado::Schema object

=cut
sub db_connect
{
  my ($host, $database, $username, $password) = @_;
  return Bio::Chado::Schema->connect("dbi:Pg:database=$database;host=$host",
                                     $username, $password,
                                     { auto_savepoint => 1,
                                       pg_enable_utf8 => 1 });
}

=head2 id_of_cvterm

 Usage   : my $termid = PomBase::Chado::id_of_cvterm($cvterm);
 Function: Return the term ID of a cvterm (eg. "GO:0000278") by
           querying its dbxref.
 Args    : $cvterm - the Cvterm ref
 Returns : the ID

=cut
sub id_of_cvterm
{
  my $cvterm = shift;

  my $dbxref = $cvterm->dbxref();
  return $dbxref->db()->name() . ':' . $dbxref->accession();
}

1;
