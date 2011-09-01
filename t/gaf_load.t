use perl5i::2;

use Test::More tests => 5;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::GeneAssociationFile;

my $importer =
  PomBase::Import::GeneAssociationFile->new(chado => $chado,
                                            config => $config);

open my $fh, '<', "data/gene_association.goa.small" or die;

$importer->load($fh);

my $annotations = $chado->resultset('Sequence::FeatureCvterm');

is($annotations->count(), 9);

sleep 100;
