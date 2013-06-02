use perl5i::2;
use Test::More tests => 2;
use Test::Deep;

use PomBase::TestUtil;
use PomBase::Import::PhenotypeAnnotation;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

my @options = ();

my $importer =
  PomBase::Import::PhenotypeAnnotation->new(chado => $chado,
                                            config => $config,
                                            options => [@options]);

my $annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 6);

open my $fh, '<', "data/phenotype_annotation.tsv" or die;
my $res = $importer->load($fh);

$annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 13);

close $fh;
