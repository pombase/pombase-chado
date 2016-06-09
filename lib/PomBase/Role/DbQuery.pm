package PomBase::Role::DbQuery;

=head1 NAME

PomBase::Role::DbQuery - Query the db table.

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::DbQuery

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

requires 'chado';

method get_db($db_name) {
  if (!defined $db_name) {
    croak "undefined value for db name";
  }

  state $cache = {};

  return $cache->{$db_name} //
         ($cache->{$db_name} =
           $self->chado()->resultset('General::Db')->find({ name => $db_name }));
}

method get_dbxref($db_name, $dbxref_name) {
  my $db = $self->get_db($db_name);

  if (!defined $db) {
    warn "no such DB: $db_name\n";
    return undef;
  }

  state $cache = {};

  if (defined $cache->{$db_name}->{$dbxref_name}) {
    warn "     get_dbxref('$db_name', '$dbxref_name') - FOUND IN CACHE ",
      $cache->{$db_name}->{$dbxref_name}->dbxref_id(), "\n"
      if $self->verbose();
    return $cache->{$db_name}->{$dbxref_name};
  }

  my $dbxref_rs = $self->chado()->resultset('General::Dbxref');
  my $dbxref = $dbxref_rs->find({ name => $dbxref_name,
                                  db_id => $db->db_id() });

  $cache->{$db_name}->{$dbxref_name} = $dbxref;

  if (defined $dbxref) {
    warn "     get_dbxref('$db_name', '$dbxref_name') - FOUND ", $dbxref->dbxref_id(),"\n"
      if $self->verbose();
  } else {
    warn "     get_dbxref('$db_name', '$dbxref_name') - NOT FOUND\n"
      if $self->verbose();
  }

  return $dbxref;
}

