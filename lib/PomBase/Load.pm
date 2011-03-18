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

use perl5i::2;

use PomBase::External;

func _load_genes($chado, $organism) {
  my $gene_type = $chado->resultset('Cv::Cvterm')->find({ name => 'gene' });

  my $org_name = $organism->genus() . ' ' . $organism->species();
  my @res = PomBase::External::get_genes($org_name);

  my %seen_symbols = ();

  for my $gene (@res) {
    my $symbol = $gene->{symbol};
    my $primary_identifier = $gene->{primary_identifier};
    if (exists $seen_symbols{lc $symbol}) {
      croak "seen symbol twice: $symbol(from $primary_identifier) and from "
        . $seen_symbols{lc $symbol};
    }
    $chado->resultset('Sequence::Feature')->create({
      uniquename => $primary_identifier,
      name => $symbol,
      organism_id => $organism->organism_id(),
      type_id => $gene_type->cvterm_id()
    });
  }
}

func init_objects($chado) {
  my $human =
    $chado->resultset('Organism::Organism')->create({
      genus => 'Homo',
      species => 'sapiens',
      common_name => 'human',
      abbreviation => 'human',
    });

  my $scerevisiae =
    $chado->resultset('Organism::Organism')->create({
      genus => 'Saccharomyces',
      species => 'cerevisiae',
      common_name => 'Scerevisiae',
      abbreviation => 'Scerevisiae',
    });

  _load_genes($chado, $human);
  _load_genes($chado, $scerevisiae);

  return {
    organisms => {
      human => $human,
      scerevisiae => $scerevisiae,
    },
  }
}

1;
