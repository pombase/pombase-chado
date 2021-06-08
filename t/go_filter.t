use strict;
use warnings;
use Carp;


use Test::More tests => 4;
use Test::Deep;

use PomBase::TestUtil;
use PomBase::Chado::GOFilter;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

$config->{systematic_id_re} = 'SP.[CP]\w+\d+\w+\d+c?.\d';
$config->{organism_taxon_map} = {
  284812 => 4896,
};

use PomBase::Import::GeneAssociationFile;

my @options = ("--assigned-by-filter=UniProtKB,InterPro,IntAct,Reactome",
               "--remove-existing");

my $importer;

my ($out, $err) = capture {
  $importer =
    PomBase::Import::GeneAssociationFile->new(chado => $chado,
                                              config => $config,
                                              options => [@options]);
};

is ($err, "no taxon filter - annotation will be loaded for all taxa\n");

open my $fh, '<', "data/gene_association.goa.small" or die;
my $deleted_counts = $importer->load($fh);
cmp_deeply($deleted_counts,
           {
             IntAct => 0,
             InterPro => 0,
             Reactome => 0,
             UniProtKB => 0,
           });
my $annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 15);
close $fh;


my $filter = PomBase::Chado::GOFilter->new(chado => $chado,
                                           config => $config);

$filter->process();

$annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 10);
