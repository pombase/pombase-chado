use strict;
use warnings;
use Carp;


use Test::More tests => 12;
use MooseX::QuietCarping;

use PomBase::TestUtil;
use PomBase::TestBase;

my $test_util = PomBase::TestUtil->new();
my $test = PomBase::TestBase->with_traits(qw(Role::OrganismFinder Role::DbQuery Role::CvQuery))->new(chado => $test_util->chado());

sub check_organism
{
  my $org = shift;

  is($org->genus(), 'Schizosaccharomyces');
  is($org->species(), 'pombe');
  is($org->common_name(), 'pombe');
  is(($org->organismprops()->all())[0]->value(), '4896');
}

check_organism($test->find_organism_by_common_name('pombe'));
check_organism($test->find_organism_by_full_name('Schizosaccharomyces pombe'));
check_organism($test->find_organism_by_taxonid('4896'));
