use strict;
use warnings;
use Carp;


use Test::More tests => 6;
use MooseX::QuietCarping;

use PomBase::TestUtil;
use PomBase::TestBase;

my $test_util = PomBase::TestUtil->new();
my $test = PomBase::TestBase->with_traits(qw(Role::DbQuery Role::CvQuery))->new(chado => $test_util->chado());

my $cvterm = $test->get_cvterm('relations', 'is_a');
ok($cvterm);

$cvterm = $test->get_relation_cvterm('is_a');
ok($cvterm);

$cvterm = $test->find_cvterm_by_name('relations', 'is_a');
ok($cvterm);

$cvterm = $test->find_cvterm_by_name('relations', 'isa');
ok($cvterm);

$cvterm = $test->find_cvterm_by_name('relations', 'ISA');
ok($cvterm);

$cvterm = $test->find_cvterm_by_term_id('OBO_REL:is_a');
ok($cvterm);
