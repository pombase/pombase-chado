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
use Webservice::InterMine 0.9412;

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
func get_genes($species) {
  my $service_uri;
  given ($species){
    when ('Homo sapiens') {
      $service_uri = 'http://www.metabolicmine.org/beta/service';
    }
    when ('Saccharomyces cerevisiae') {
      $service_uri =
        'http://yeastmine-test.yeastgenome.org/yeastmine-dev/service';
    }
    default {
      croak "unknown species: $species";
    }
  }

  my $service = Webservice::InterMine->get_service($service_uri);


  my $query = $service->new_query;

  my $primary_tag = 'Gene.primaryIdentifier';
  my $secondary_tag = 'Gene.secondaryIdentifier';
  my $name_tag = 'Gene.name';
  my $symbol_tag = 'Gene.symbol';

  my @view = ($primary_tag, $secondary_tag, $name_tag, $symbol_tag);

  $query->add_view(@view);

  $query->add_constraint(
    path  => 'Gene.primaryIdentifier',
    op    => 'IS NOT NULL',
  );

  $query->add_constraint(
    path  => 'Gene.organism.name',
    op    => '=',
    value => $species,
  );

  my $res = $query->results(as => 'hashrefs');

  return map {
    my $secondary_identifier = $_->{$secondary_tag} // $_->{$primary_tag};
    {
      primary_identifier => $_->{$primary_tag},
      secondary_identifier => $secondary_identifier,
      name => $_->{$name_tag},
      symbol => $_->{$symbol_tag},
      description => $_->{$symbol_tag},
    }
  } @$res;
}

1;
