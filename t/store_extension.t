use perl5i::2;

use Test::More tests => 11;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Chado::ExtensionProcessor;

my $fc_rs = $chado->resultset('Sequence::FeatureCvterm');

my $SPBC2F12_13_spindle_fc;
my $SPAC2F7_03c_spindle_fc;
my $spindle_cvterm;

while (defined (my $fc = $fc_rs->next())) {
  if ($fc->cvterm()->name() eq 'spindle pole body') {
    $spindle_cvterm = $fc->cvterm();
    if ($fc->feature()->uniquename() eq 'SPBC2F12.13.1') {
      $SPBC2F12_13_spindle_fc = $fc;
    } else {
      if ($fc->feature()->uniquename() eq 'SPAC2F7.03c.1') {
        $SPAC2F7_03c_spindle_fc = $fc;
      }
    }
  }
}

ok (defined $SPBC2F12_13_spindle_fc);
ok (defined $SPAC2F7_03c_spindle_fc);

my $extensions = [
  {
    'identifier' => 'Pfam:PF00069',
    'rel_name' => 'dependent_on',
  },
];

my $ex_processor = PomBase::Chado::ExtensionProcessor->new(verbose => 0, chado => $chado, config => $config);
my $new_cvterm = $ex_processor->store_extension($SPBC2F12_13_spindle_fc, $extensions);

ok ($new_cvterm->cvterm_id() != $spindle_cvterm->cvterm_id());
is ($new_cvterm->name(), 'spindle pole body [dependent_on] Pfam:PF00069');

# check new term parent
my $new_term_isa_rel =
  $chado->resultset('Cv::CvtermRelationship')->search({ subject_id => $new_cvterm->cvterm_id(),
                                                        object_id => $spindle_cvterm->cvterm_id() });

is ($new_term_isa_rel->count(), 1);

my $new_term_props_rs = $new_cvterm->cvtermprops();

is ($new_term_props_rs->count(), 2);

my $new_term_prop = $new_term_props_rs->first();

is ($new_term_prop->value, 'Pfam:PF00069');
is ($new_term_prop->type()->name(), 'annotation_extension_relation-dependent_on');

# delete the property and check that it's re-created
$new_term_prop->delete();

is ($new_cvterm->cvtermprops()->count(), 1);

# new processor with a fresh cache
$ex_processor = PomBase::Chado::ExtensionProcessor->new(verbose => 0, chado => $chado, config => $config, pre_init_cache => 1);

sub check_SPAC2F7_03c {
  my $new_cvterm_after_prop_delete = $ex_processor->store_extension($SPAC2F7_03c_spindle_fc, $extensions);
  my $new_cvterm_after_delete_prop_rs = $new_cvterm_after_prop_delete->cvtermprops();
  is ($new_cvterm_after_delete_prop_rs->count(), 1);
}

check_SPAC2F7_03c();

# reset the fc to check that we don't create more props for the
# extended term if we use it again

$SPAC2F7_03c_spindle_fc->cvterm($spindle_cvterm);
$SPAC2F7_03c_spindle_fc->update();

check_SPAC2F7_03c();


