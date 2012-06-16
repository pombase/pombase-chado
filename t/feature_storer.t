use perl5i::2;

use Test::More tests => 4;

use PomBase::TestUtil;
use PomBase::TestBase;

my $test_util = PomBase::TestUtil->new();
my $config = $test_util->config();

package TestStorer;

use Moose;

extends 'PomBase::TestBase';

has organism => (is => 'rw');


package main;

my $chado = $test_util->chado();

my $organism = $chado->resultset('Organism::Organism')->find({ genus => 'Schizosaccharomyces',
                                                               species => 'pombe' });

my $test = TestStorer->with_traits(qw(Role::FeatureStorer Role::ConfigUser))
              ->new(chado => $chado, config => $config,
                    organism => $organism);

my $gene_uniquename = 'test-gene';

my $new_uniquename = $test->get_new_uniquename("$gene_uniquename.");
is($new_uniquename, 'test-gene.1');

my $feat1 = $test->store_feature("$gene_uniquename.1", 'test-name', [], 'gene');
my $feat2 = $test->store_feature("$gene_uniquename.3", 'test-name', [], 'gene');

$new_uniquename = $test->get_new_uniquename("$gene_uniquename.");
is($new_uniquename, 'test-gene.4');

$new_uniquename = $test->get_new_uniquename("$gene_uniquename-other.");
is($new_uniquename, 'test-gene-other.1');

$new_uniquename = $test->get_new_uniquename("$gene_uniquename-other.", 5);
is($new_uniquename, 'test-gene-other.5');
