package PomBase::Import::ReferencesFile;

=head1 NAME

PomBase::Import::ReferencesFile - Read a flat file of references

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::ReferencesFile

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

use Moose;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

sub _store {
  my $self = shift;
  my $uniquename = shift;
  my $title = shift;
  my $authors = shift;
  my $year = shift;
  my $abstract = shift;

  my $pub = $self->find_or_create_pub($uniquename);
  $pub->title($title) if $title;
  $pub->pyear($year) if $year;
  $pub->update();

  $self->create_pubprop($pub, 'authors', $authors) if $authors;
  $self->create_pubprop($pub, 'abstract', $abstract) if $abstract;
}

sub load {
  my $self = shift;
  my $fh = shift;


  my $uniquename = undef;
  my $title = undef;
  my $authors = undef;
  my $year = undef;
  my $abstract = undef;

 LINE:
  while (<$fh>) {
    next if /^#|^!/;

    chomp $_;

    s/^\s+//;

    if (/^(?:pb_)?ref_id:\s*(.*)/) {
      if ($uniquename) {
        $self->_store($uniquename, $title, $authors, $year, $abstract);
        $uniquename = undef;
        $title = undef;
        $authors = undef;
        $year = undef;
        $abstract = undef;
      }
      $uniquename = $1;
    }

    if (/^title:\s*(.*)/) {
      $title = $1;
    }
    if (/^authors:\s*(.*)/) {
      $authors = $1;
    }
    if (/^year:\s*(.*)/) {
      $year = $1;
    }
    if (/^abstract:\s*(.*)/) {
      $abstract = $1;
    }
  }

  if ($uniquename) {
    $self->_store($uniquename, $title, $authors, $year, $abstract);
  }
}

1;
