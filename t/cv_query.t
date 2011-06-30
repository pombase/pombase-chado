use perl5i::2;

use Test::More tests => 5;
use MooseX::QuietCarping;

{
  package Test;
  use perl5i::2;
  use Moose;

  with 'PomBase::Role::ChadoUser';
  with 'PomBase::Role::CvQuery';

  method verbose
  {
    return 0;
  }

  no Moose;
}

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $test = Test->new(chado => $test_util->chado());

my $cvterm = $test->get_cvterm('relationship', 'is_a');
ok($cvterm);

$cvterm = $test->find_cvterm('relationship', 'is_a');
ok($cvterm);

$cvterm = $test->find_cvterm('relationship', 'isa');
ok($cvterm);

$cvterm = $test->find_cvterm('relationship', 'ISA');
ok($cvterm);

$cvterm = $test->find_cvterm_by_accession('OBO_REL:is_a');
ok($cvterm);
