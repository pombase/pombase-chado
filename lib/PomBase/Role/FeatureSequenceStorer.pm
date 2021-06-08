package PomBase::Role::FeatureSequenceStorer;

=head1 NAME

PomBase::Role::FeatureSequenceStorer - store sequences in the residues field

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::FeatureSequenceStorer

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

sub store_feature_sequence {
  my $self = shift;
  my $feature = shift;
  my $chromosome = shift;
  my $strand = shift;
  my $start = shift;
  my $end = shift;
  my $phase = shift;

  my $chr_sequence = $chromosome->residues();

  if ($end > length $chr_sequence) {
    warn "chromosome sequence (length: ", length $chr_sequence,
      ") too short for range: $start..$end - not storing sequence for ",
      $feature->uniquename(), "\n";
    return;
  }

  my $sub_seq = substr $chr_sequence, $start - 1, $end - $start + 1;

  if ($strand == -1) {
    $sub_seq = reverse $sub_seq;
    $sub_seq =~ tr/ACGTacgt/TGCAtgca/;
  }

  $feature->residues($sub_seq);
  $feature->update();
}

1;
