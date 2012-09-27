use perl5i::2;

use Test::More tests => 4;

use PomBase::TestUtil;
use PomBase::TestBase;

my $test_util = PomBase::TestUtil->new();
my $config = $test_util->config();

use PomBase::Role::ExtensionDisplayer;
use PomBase::Chado::ExtensionProcessor;

package TestDisplayer;

use Moose;

has chado => (is => 'rw');

with 'PomBase::Role::ExtensionDisplayer';
with 'PomBase::Role::CvQuery';


package main;

my $chado = $test_util->chado();

my $test_obj = TestDisplayer->new(chado => $chado);

my $fc_rs = $chado->resultset('Sequence::FeatureCvterm');

my $SPBC2F12_13_spindle_fc;

while (defined (my $fc = $fc_rs->next())) {
  if ($fc->feature()->uniquename() eq 'SPBC2F12.13.1') {
    $SPBC2F12_13_spindle_fc = $fc;
  }
}

my $go_term = $test_obj->find_cvterm_by_term_id('GO:0034763');

ok (defined $SPBC2F12_13_spindle_fc);

my $extensions = [
  {
    identifier => 'Pfam:PF00069',
    rel_name => 'dependent_on',
  },
  {
    term => $go_term,
    rel_name => 'exists_during',
  }
];

my $ex_processor = PomBase::Chado::ExtensionProcessor->new(verbose => 0, chado => $chado, config => $config);
my $new_cvterm = $ex_processor->store_extension($SPBC2F12_13_spindle_fc, $extensions);

my $gaf_display_string = $test_obj->make_gaf_extension($SPBC2F12_13_spindle_fc);

is($gaf_display_string, "foo");
