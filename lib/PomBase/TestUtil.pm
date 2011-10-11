package PomBase::TestUtil;

=head1 NAME

PomBase::TestUtil - Utility methods for testing the PomBase code

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::TestUtil

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
use YAML qw(LoadFile);
use File::Temp qw(tempfile);

use Bio::Chado::Schema;
use PomBase::Chado::IdCounter;

has config => (is => 'rw', init_arg => undef, isa => 'HashRef');
has test_config => (is => 'rw', init_arg => undef, isa => 'HashRef');
has chado => (is => 'rw', init_arg => undef, isa => 'Bio::Chado::Schema');
has verbose => (is => 'rw');

with 'PomBase::Role::CvQuery';

my $TEST_CONFIG_FILE = 't/test_config.yaml';

method _make_test_db
{
  my ($fh, $temp_db) = tempfile(UNLINK => 1);
  system "sqlite3 $temp_db < t/chado_schema.sql";
  return Bio::Chado::Schema->connect("dbi:SQLite:$temp_db");
}

method _populate_db($chado)
{
  my $test_data = $self->test_config()->{data};

  my $cv_conf = $test_data->{cv};
  for my $row (@$cv_conf) {
    $chado->resultset("Cv::Cv")->create($row);
  }

  my $db_conf = $test_data->{db};
  for my $row (@$db_conf) {
    $chado->resultset("General::Db")->create($row);
  }

  my $pub_conf = $test_data->{pub};
  for my $row (@$pub_conf) {
    $chado->resultset("Pub::Pub")->create($row);
  }

  my $org_data = $self->test_config()->{test_organism};
  my $organism =
    $chado->resultset('Organism::Organism')->create({
      genus => $org_data->{genus},
      species => $org_data->{species},
    });

  $chado->resultset('Organism::Organismprop')->create({
    value => $org_data->{taxonid},
    type => {
      name => 'taxon_id',
      cv => {
        name => 'PomBase organism property types',
      }
    },
    organism_id => $organism->organism_id(),
  });

  my $gene_type = $self->get_cvterm('sequence', 'gene');
  my $mrna_type = $self->get_cvterm('sequence', 'mRNA');

  for my $gene_data (@{$self->test_config()->{test_genes}}) {
    $chado->resultset('Sequence::Feature')->create({
      uniquename => $gene_data->{uniquename},
      organism_id => $organism->organism_id(),
      type_id => $gene_type->cvterm_id(),
    });
    $chado->resultset('Sequence::Feature')->create({
      uniquename => $gene_data->{uniquename} . '.1',
      organism_id => $organism->organism_id(),
      type_id => $mrna_type->cvterm_id(),
    });
  }
}

method BUILD
{
  my ($fh, $temp_db) = tempfile();

  my $test_config = LoadFile($TEST_CONFIG_FILE);
  $self->test_config($test_config);

  my $config = LoadFile('load-chado.yaml');
  my $id_counter = PomBase::Chado::IdCounter->new();
  $config->{id_counter} = $id_counter;
  $self->config($config);

  my $chado = $self->_make_test_db();
  $self->chado($chado);
  $self->_populate_db($chado);
}

1;
