package PomBase::Role::CvtermCreator;

=head1 NAME

PomBase::Role::CvtermCreator - Code for creating new cvterms

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::CvtermCreator

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

requires 'get_cv';
requires 'get_cvterm';
requires 'chado';
requires 'config';
requires 'find_or_create_dbxref';
requires 'find_db_by_name';

method create_cvterm($cv_name, $db_name, $id_counter, $term_name)
{
  my $formatted_id = $id_counter->get_formatted_id($db_name);

  my $cv = $self->get_cv($cv_name);

  my $db = $self->find_db_by_name($db_name);
  my $new_dbxref = $self->find_or_create_dbxref($db, $formatted_id);

  return
    $self->chado()->resultset('Cv::Cvterm')->find_or_create({
      cv_id => $cv->cv_id(),
      dbxref_id => $new_dbxref->dbxref_id(),
      name => $term_name,
    });
}


method find_or_create_cvterm($cv, $term_name) {
  if (!ref $cv) {
    $cv = $self->get_cv($cv);
  }

  warn "    find_or_create_cvterm('", $cv->name(), "', '$term_name'\n"
    if $self->verbose();

  my $cvterm = $self->find_cvterm_by_name($cv, $term_name);

  # nested transaction
  my $cvterm_guard = $self->chado()->txn_scope_guard();

  if (defined $cvterm) {
    warn "    found cvterm_id ", $cvterm->cvterm_id(),
      " when looking for $term_name in ", $cv->name(),"\n" if $self->verbose();
  } else {
    warn "    failed to find: $term_name in ", $cv->name(), "\n" if $self->verbose();

    my $db = $self->objs()->{dbs_objects}->{$cv->name()};
    if (!defined $db) {
      die "no database for cv: ", $cv->name();
    }

    my $formatted_id =
      $self->config()->{id_counter}->get_formatted_id($db->name());

    my $dbxref_rs = $self->chado()->resultset('General::Dbxref');

    die "no db for ", $cv->name(), "\n" if !defined $db;

    warn "    creating dbxref $formatted_id, ", $cv->name(), "\n" if $self->verbose();

    my $dbxref =
      $dbxref_rs->create({ db_id => $db->db_id(),
                           accession => $formatted_id });

    my $cvterm_rs = $self->chado()->resultset('Cv::Cvterm');
    $cvterm = $cvterm_rs->create({ name => $term_name,
                                   dbxref_id => $dbxref->dbxref_id(),
                                   cv_id => $cv->cv_id() });

    warn "    created new cvterm, id: ", $cvterm->cvterm_id(), "\n" if $self->verbose();
  }

  $cvterm_guard->commit();

  return $cvterm;
}

1;
