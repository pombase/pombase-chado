package PomBase::Load;

=head1 NAME

PomBase::Load - Code for initialising and loading data into the PomBase Chado
                database

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Load

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use PomBase;
use perl5i::2;

func init_objects($chado) {
  my $human_organism =
    $chado->resultset('Organism::Organism')->create({
      genus => 'Homo',
      species => 'sapiens',
      common_name => 'human',
      abbreviation => 'human',
    });

  my $scerevisiae_organism =
    $chado->resultset('Organism::Organism')->create({
      genus => 'Saccharomyces',
      species => 'cerevisiae',
      common_name => 'Scerevisiae',
      abbreviation => 'Scerevisiae',
    });

  return {
    organisms => {
      human => $human_organism,
      scerevisiae => $scerevisiae_organism,
    },
  }
}

1;
