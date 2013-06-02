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
has load_test_features => (is => 'rw', default => 1);

with 'PomBase::Role::CvQuery';

my $TEST_CONFIG_FILE = 't/test_config.yaml';

method _make_test_db
{
  my ($fh, $temp_db) = tempfile(UNLINK => 1);
  system "sqlite3 $temp_db < t/chado_schema.sql";
  return Bio::Chado::Schema->connect("dbi:SQLite:$temp_db");
}

method _load_cv($chado, $cv_conf)
{
  for my $row (@$cv_conf) {
    $chado->resultset("Cv::Cv")->create($row);
  }
}

method _load_feature_cvterms($chado, $feature_cvterm_conf)
{
  for my $row (@$feature_cvterm_conf) {
    $chado->resultset("Sequence::FeatureCvterm")->create($row);
  }
}

method _load_feature_relationships($chado, $feature_rel_conf)
{
  for my $row (@$feature_rel_conf) {
    $chado->resultset("Sequence::FeatureRelationship")->create($row);
  }
}

method _load_cv_db($chado)
{
  my $test_data = $self->test_config()->{data};

  my $cv_conf = $test_data->{cv};
  $self->_load_cv($chado, $cv_conf);

  my $db_conf = $test_data->{db};
  for my $row (@$db_conf) {
    $chado->resultset("General::Db")->create($row);
  }

  my $cvterm_rels_conf = $test_data->{cvterm_relationships};
  for my $row (@$cvterm_rels_conf) {
    $chado->resultset("Cv::CvtermRelationship")->create($row);
  }

  my $cvtermpaths_conf = $test_data->{cvtermpath};
  for my $row (@$cvtermpaths_conf) {
    $chado->resultset("Cv::Cvtermpath")->create($row);
  }
}

method _load_test_features($chado)
{
  my $test_data = $self->test_config()->{data};

  $self->_load_cv($chado, $test_data->{extra_cvterm_terms});

  my $pub_conf = $test_data->{pub};
  for my $row (@$pub_conf) {
    $chado->resultset("Pub::Pub")->create($row);
  }

  my %orgs_by_taxon = ();

  my @org_data_list = @{$self->test_config()->{test_organisms}};

  for my $org_data (@org_data_list) {
    my $organism =
      $chado->resultset('Organism::Organism')->create({
        genus => $org_data->{genus},
        species => $org_data->{species},
        common_name => $org_data->{common_name},
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

    $orgs_by_taxon{$org_data->{taxonid}} = $organism;

    if ($self->verbose()) {
      warn " added org: ", $org_data->{taxonid}, "\n";
    }
  }

  my $gene_type = $self->get_cvterm('sequence', 'gene');
  my $mrna_type = $self->get_cvterm('sequence', 'mRNA');
  my $allele_type = $self->get_cvterm('sequence', 'allele');

  for my $gene_data (@{$self->test_config()->{test_genes}}) {
    my $organism = $orgs_by_taxon{$gene_data->{taxonid}};
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

    if (exists $gene_data->{alleles}) {
      for my $allele_data (@{$gene_data->{alleles}}) {
        $chado->resultset('Sequence::Feature')->create({
          uniquename => $allele_data->{uniquename},
          organism_id => $organism->organism_id(),
          type_id => $allele_type->cvterm_id(),
        });

      }
    }
  }

  $self->_load_feature_cvterms($chado, $test_data->{feature_cvterm});
  $self->_load_feature_relationships($chado, $test_data->{feature_relationships});
}

method BUILD
{
  my ($fh, $temp_db) = tempfile();

  my $test_config = LoadFile($TEST_CONFIG_FILE);
  $self->test_config($test_config);

  my $allele_type_cv_name = "PomBase allele types";

  my $config = LoadFile('load-chado.yaml');
  $self->config($config);

  push @{$test_config->{data}->{cv}},
    {
      name => $allele_type_cv_name,
      cvterms => [
        map {
          {
            name => $_->{name},
            dbxref => {
              accession => $_->{name},
              db => {
                name => $allele_type_cv_name,
              },
            },
          };
        } @{$self->config()->{cvs}->{$allele_type_cv_name}}
      ],
    };

  my $chado = $self->_make_test_db();
  my $id_counter = PomBase::Chado::IdCounter->new(config => $config,
                                                  chado => $chado);
  $config->{id_counter} = $id_counter;

  $self->chado($chado);
  $self->_load_cv_db($chado);
  if ($self->load_test_features()) {
    $self->_load_test_features($chado);
  }
}

1;
