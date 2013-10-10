package PomBase::Chado::IdCounter;

=head1 NAME

PomBase::Chado::IdCounter - Code to provide unique db accessions

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::IdCounter

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

my %new_cvterm_ids = ();

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';

# return a new ID in the given db
method get_dbxref_id($db_name) {
  if (!exists $new_cvterm_ids{$db_name}) {
    my $db = $self->chado()->resultset('General::Db')->find({ name => $db_name });
    my $rs = $self->chado()->resultset('General::Dbxref')->search({ db_id => $db->db_id(),
                                                                  accession => { like => '0______' }},
                                                                  { order_by => { -desc => 'accession' }});
    my $largest = $rs->first();
    my $new_num = $largest->accession() + 1;
    $new_cvterm_ids{$db_name} = $new_num;
  }

  return $new_cvterm_ids{$db_name}++;
}

method get_formatted_id($db_name)
{
  return sprintf "%07d", $self->get_dbxref_id($db_name);
}

1;
