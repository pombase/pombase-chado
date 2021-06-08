package PomBase::Role::FeatureDumper;

=head1 NAME

PomBase::Role::FeatureDumper - Code for dumping the contents of a BioPerl
                               feature as text

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::FeatureDumper

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

use Carp;

use Moose::Role;

sub dump_feature {
  my $self = shift;
  my $feature = shift;

  my $loc = $feature->location();

  my $seq = $feature->entire_seq();
  my $seq_display_id = $seq->display_id();

  my $loc_text =  $seq_display_id . '-' .
      '_' . $loc->start() . '..' . $loc->end();
  warn " loc: $loc_text\n";
  for my $tag ($feature->get_all_tags) {
    warn "    tag: ", $tag, "\n";
    for my $value ($feature->get_tag_values($tag)) {
      warn "      value: ", $value, "\n";
    }
  }
}

1;
