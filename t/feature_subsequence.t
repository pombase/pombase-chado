use strict;
use warnings;
use Test::More tests => 9;

use PomBase::TestUtil;
use PomBase::TestBase;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();

my $test_obj = PomBase::TestBase->with_traits(qw(Role::FeatureSubsequence))->new(chado => $chado);

my $feat = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPBC2F12.13.1' });

is ($test_obj->feature_subseq($feat, 1, 10), 'atcaccttgt');
is ($test_obj->feature_subseq($feat, 16, 30), 'cctttctagcccatg');
is ($test_obj->feature_subseq($feat, 50, 70), 'agccatatcactgtcggcatg');

eval {
  $test_obj->feature_subseq($feat, 40, 30);
  fail "feature_subseq() should throw error";
};
like ($@, qr/start position 40 is greater than end position 30 in feature_subseq/);

eval {
  $test_obj->feature_subseq($feat, 0, 30);
  fail "feature_subseq() should throw error";
};
like ($@, qr/start position 0 is less than 1 in feature_subseq/);

my $rev_feat = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPAC2F7.03c.1' });

is ($test_obj->feature_subseq($rev_feat, 1, 5), 'ctgac');
is ($test_obj->feature_subseq($rev_feat, 26, 35), 'ggcaaataaa');
is ($test_obj->feature_subseq($rev_feat, 36, 40), 'ttctt');

eval {
  $test_obj->feature_subseq($rev_feat, 30, 9999);
  fail "feature_subseq() should throw out of range error";
};
like ($@, qr/end position 9999 out of range in feature_subseq/);
