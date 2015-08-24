use perl5i::2;

use Test::More tests => 5;
use MooseX::QuietCarping;

use PomBase::TestUtil;
use PomBase::TestBase;

my $test_util = PomBase::TestUtil->new();
my $test = PomBase::TestBase->with_traits(qw(Role::DbQuery Role::CvQuery))->new(chado => $test_util->chado());

my $cvterm = $test->get_cvterm('relationship', 'is_a');
ok($cvterm);

$cvterm = $test->find_cvterm_by_name('relationship', 'is_a');
ok($cvterm);

$cvterm = $test->find_cvterm_by_name('relationship', 'isa');
ok($cvterm);

$cvterm = $test->find_cvterm_by_name('relationship', 'ISA');
ok($cvterm);

$cvterm = $test->find_cvterm_by_term_id('OBO_REL:is_a');
ok($cvterm);
