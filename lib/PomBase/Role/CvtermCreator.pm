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

use strict;
use warnings;
use Carp;

use Try::Tiny;

use Moose::Role;

requires 'get_cv';
requires 'chado';
requires 'config';
requires 'find_or_create_dbxref';
requires 'find_db_by_name';
requires 'get_db';

sub create_cvterm {
  my $self = shift;
  my $cv_name = shift;
  my $db_name = shift;
  my $id_counter = shift;
  my $term_name = shift;

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


sub find_or_create_cvterm {
  my $self = shift;
  my $cv = shift;
  my $term_name = shift;

  if (!defined $cv) {
    croak "undefined cv";
  }

  if (!ref $cv) {
    $cv = $self->get_cv($cv);
  }

  warn "    find_or_create_cvterm('", $cv->name(), "', '$term_name'\n"
    if $self->verbose();

  my $cvterm = $self->find_cvterm_by_name($cv, $term_name);

  if (defined $cvterm) {
    warn "    found cvterm_id ", $cvterm->cvterm_id(),
      " when looking for $term_name in ", $cv->name(),"\n" if $self->verbose();
  } else {
    warn "    failed to find: $term_name in ", $cv->name(), "\n" if $self->verbose();

    # nested transaction
    my $cvterm_guard = $self->chado()->txn_scope_guard();

    my $db_name = $self->config->{db_name_for_cv};

    die if $db_name eq 'warning';

    my $db = $self->get_db($db_name);

    if (!defined $db) {
      $db = $self->chado()->resultset('General::Db')->create({ name => $db_name });
    }

    my $formatted_id;

    try {
      $formatted_id = $self->config()->{id_counter}->get_formatted_id($db->name());
    } catch {
      die "failed to get the next ", $db->name(), " ID for storing $term_name: $_";
    };

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

    $cvterm_guard->commit();

    warn "    created new cvterm, id: ", $cvterm->cvterm_id(), "\n" if $self->verbose();
  }

  die 'no cvterm found or created for: ' . $cv->name() . ' ' . $term_name unless defined $cvterm;

  return $cvterm;
}

1;
