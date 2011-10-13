use perl5i::2;

use Test::More tests => 2;
use Test::Deep;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::GeneAssociationFile;

my @options = ("--assigned-by-filter=UniProtKB,InterPro,IntAct,Reactome",
               "--remove-existing");

my $importer =
  PomBase::Import::GeneAssociationFile->new(chado => $chado,
                                            config => $config,
                                            options => [@options]);

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
is($annotations->count(), 6);
close $fh;

# make sure we can re-load, existing data should be deleted
open $fh, '<', "data/gene_association.goa.small" or die;
$deleted_counts = $importer->load($fh);
cmp_deeply($deleted_counts,
           {
             IntAct => 1,
             InterPro => 2,
             Reactome => 1,
             UniProtKB => 2,
           });
$annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 6);
close $fh;
