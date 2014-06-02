package PomBase::Chado::GeneExQualifiersUtil;

=head1 NAME

PomBase::Chado::GeneExQualifiers - Code for reading gene expression qualifiers

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::GeneExQualifiers

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

method read_qualifiers($gene_ex_qualifiers) {
  open my $fh, '<', $gene_ex_qualifiers
    or die "can't opn $gene_ex_qualifiers: $!";

  my @ret_val = ();

  while (defined (my $line = <$fh>)) {
    next if $line =~ /^!/;

    chomp $line;

    push @ret_val, $line;
  }

  close $fh;

  return \@ret_val;
}

1;
