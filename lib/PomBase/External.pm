package PomBase::External;

=head1 NAME

PomBase::External - PomBase code for retrieving external data

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::External

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DBEntry;

=head2 get_genes

 Usage   : my @results = PomBase::External::get_genes('Homo sapiens');
           for my $res (@results) {
             my $primary_identifier = $res->{primary_identifier};
             my $symbol = $res->{symbol}
             ...
           }
 Function: Get data about the genes of a given species, using web services.
           Only returns those that have primary_identifier and a symbol
 Args    : $species
 Returns : an array of arrays of results

=cut
func get_genes($config, $species) {
  (my $ensembl_species = "\L$species") =~ s/ /_/g;

  my $ensembl_conf = $config->{ensembl_dbs}->{$species};

  my $db =
    Bio::EnsEMBL::DBSQL::DBAdaptor->new(
      '-host'    => $ensembl_conf->{host},
      '-port'    => $ensembl_conf->{port},
      '-user'    => $ensembl_conf->{user},
      '-group'   => $ensembl_conf->{group},
      '-species' => $ensembl_species,
      '-dbname'  => $ensembl_conf->{dbname},
    );

  my $slice_adaptor = $db->get_sliceAdaptor();
  my $slices        = $slice_adaptor->fetch_all('toplevel');

  my @gene_data;

  my %seen_chromosomes = ();

  SLICE: while (my $slice = shift @{$slices})
  {
    my $slice_identifier = $slice->seq_region_name();
    my $genes = $slice->get_all_Genes;   # load genes lazily - then they can be dumped later

    for my $gene (@$genes) {
      push @gene_data, {
        primary_identifier => $gene->stable_id(),
        secondary_identifier => $gene->external_name(),
      };
    }

    warn "Processed ", scalar(@$genes), " genes from slice $slice_identifier\n";
  }

  return @gene_data;
}

1;
