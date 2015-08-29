use strict;
use warnings;
use Test::More tests => 1;

use PomBase::TestUtil;
use PomBase::TestBase;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();

my $test_obj = PomBase::TestBase->with_traits(qw(
      Role::SeqTranslate
  ))->new(config => $test_util->config(), chado => $chado);

is ($test_obj->translate('atgtgctgccagtgc'), 'MCCQC');
