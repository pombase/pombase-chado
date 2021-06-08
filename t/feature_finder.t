use strict;
use warnings;
use Carp;

use Try::Tiny;

use Test::More tests => 13;

use PomBase::TestUtil;
use PomBase::TestBase;

my $test_util = PomBase::TestUtil->new();
my $config = $test_util->config();

package TestFinder;

use Moose;

extends 'PomBase::TestBase';
with 'PomBase::Role::FeatureFinder';


package main;

my $chado = $test_util->chado();

my $organism = $chado->resultset('Organism::Organism')->find({ genus => 'Schizosaccharomyces',
                                                               species => 'pombe' });

my $test = TestFinder->new(chado => $chado, config => $config,
                           organism => $organism);

my $klp5_feature = $test->find_chado_feature('SPBC2F12.13');
is ($klp5_feature->name(), 'klp5');

try {
  $klp5_feature = $test->find_chado_feature('klp5');
  fail "shouldn't be able to find klp5 by name";
} catch {
  chomp (my $message = $_);
  is ($message, "can't find feature for: klp5");
};

$klp5_feature = $test->find_chado_feature('klp5', 1);
is ($klp5_feature->uniquename(), 'SPBC2F12.13');

try {
  $klp5_feature = $test->find_chado_feature('KLP5', 1);
  fail "shouldn't be able to find klp5 by name with the wrong case";
} catch {
  chomp (my $message = $_);
  is ($message, "can't find feature for: KLP5");
};

$klp5_feature = $test->find_chado_feature('KLP5', 1, 1);
is ($klp5_feature->uniquename(), 'SPBC2F12.13');

$klp5_feature = $test->find_chado_feature('klp5', 1, 0, $organism);
is ($klp5_feature->uniquename(), 'SPBC2F12.13');

$klp5_feature = $test->find_chado_feature('klp5', 1, 0, $organism);
is ($klp5_feature->uniquename(), 'SPBC2F12.13');

my $ssm4_feature = $test->find_chado_feature('ssm4', 1, 0, $organism, ['gene', 'pseudogene']);
is ($ssm4_feature->uniquename(), 'SPAC27D7.13c');

my $ssm4_m1_feature = $test->find_chado_feature('ssm4-m1', 1, 0, $organism, ['allele']);
is ($ssm4_m1_feature->uniquename(), 'SPAC27D7.13c:allele-1');

$ssm4_m1_feature = $test->find_chado_feature('ssm4-m1', 1, 0, $organism);
is ($ssm4_m1_feature->uniquename(), 'SPAC27D7.13c:allele-1');

try {
  my $ssm4_feature_fail = $test->find_chado_feature('ssm4', 1, 0, $organism, ['pseudogene']);
  fail "find_chado_feature() ssm4 + pseudogene should have failed but got: ",
    $ssm4_feature_fail->uniquename();
} catch {
  chomp (my $message = $_);
  is ($message, "can't find feature for: ssm4");
};

try {
  my $ensg00000124562_feature = $test->find_chado_feature('ENSG00000124562', 0, 0, $organism);
  fail "find_chado_feature() shouldn't find human gene: ",
    $ensg00000124562_feature->uniquename();
} catch {
  chomp (my $message = $_);
  is ($message, "can't find feature for: ENSG00000124562");
};

my $ensg00000124562_feature = $test->find_chado_feature('ENSG00000124562');
is ($ensg00000124562_feature->uniquename(), 'ENSG00000124562');
