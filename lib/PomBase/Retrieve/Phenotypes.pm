package PomBase::Retrieve::Phenotypes;

=head1 NAME

PomBase::Retrieve::Phenotypes - Retrieve phenotypes from Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::Phenotypes

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

use Moose;

use Iterator::Simple qw(iterator);

with 'PomBase::Retriever';

sub retrieve {
  my $self = shift;

  my $chado = $self->chado();

  my $it = do {
    my $results =
      $chado->resultset('Cv::Cv')->search({ 'me.name' => 'phenotype' })
        ->search_related('cvterms');

    iterator {
      my $row = $results->next();
      if (defined $row) {
        my $dbxref = $row->dbxref();
        my $id = $dbxref->db()->name() . ':' . $dbxref->accession();
        return [$row->name(), $id];
      } else {
        return undef;
      }
    };
  };
}

sub header {
  my $self = shift;
  return '';
}

sub format_result {
  my $self = shift;
  my $res = shift;

  return join "\t", @$res;
}

1;
