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

use perl5i::2;
use Carp;

use Moose::Role;

method dump_feature($feature)
{
  for my $tag ($feature->get_all_tags) {
    print "    tag: ", $tag, "\n";
    for my $value ($feature->get_tag_values($tag)) {
      print "      value: ", $value, "\n";
    }
  }
}

1;
