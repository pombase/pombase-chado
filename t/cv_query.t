use perl5i::2;

use Test::More tests => 1;
use MooseX::QuietCarping;

{
  package Test;
  use perl5i::2;
  use Moose;

  with 'PomBase::Role::ChadoUser';
  with 'PomBase::Role::CvQuery';

  no Moose;
}

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $test = Test->new(chado => $test_util->chado());
my $cvterm = $test->get_cvterm('relationship', 'is_a');
ok($cvterm);
