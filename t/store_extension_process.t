use strict;
use warnings;
use Carp;


use Test::More tests => 9;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Chado::ExtensionProcessor;

my $fc_rs = $chado->resultset('Sequence::FeatureCvterm');

my $SPBC2F12_13_spindle_fc;
my $spindle_cvterm;

while (defined (my $fc = $fc_rs->next())) {
  if ($fc->cvterm()->name() eq 'spindle pole body') {
    $spindle_cvterm = $fc->cvterm();
    if ($fc->feature()->uniquename() eq 'SPBC2F12.13.1') {
      $SPBC2F12_13_spindle_fc = $fc;
    }
  }
}

ok (defined $SPBC2F12_13_spindle_fc);

my $extension_text = 'has_substrate(GeneDB_Spombe:SPAC2F7.03c),exists_during(GO:0034763),requires_feature(Pfam:PF00564)';

my $ex_processor = PomBase::Chado::ExtensionProcessor->new(verbose => 0, chado => $chado, config => $config);
my $new_cvterm = $ex_processor->process_one_annotation($SPBC2F12_13_spindle_fc, $extension_text);

ok ($new_cvterm->cvterm_id() != $spindle_cvterm->cvterm_id());
is ($new_cvterm->name(), 'spindle pole body [exists_during] negative regulation of transmembrane transport [has_substrate] SPAC2F7.03c [requires_feature] Pfam:PF00564');

# check new term parent
my $new_term_isa_rel =
  $chado->resultset('Cv::CvtermRelationship')->search({ subject_id => $new_cvterm->cvterm_id(),
                                                        object_id => $spindle_cvterm->cvterm_id() });

is ($new_term_isa_rel->count(), 1);

my $new_term_props_rs = $new_cvterm->cvtermprops()->search({}, { order_by => 'value' });

is ($new_term_props_rs->count(), 3);

my $new_term_prop_1 = $new_term_props_rs->next();
is ($new_term_prop_1->value, 'Pfam:PF00564');
is ($new_term_prop_1->type()->name(), 'annotation_extension_relation-requires_feature');

my $new_term_prop_2 = $new_term_props_rs->next();
is ($new_term_prop_2->value, 'SPAC2F7.03c');
is ($new_term_prop_2->type()->name(), 'annotation_extension_relation-has_substrate');
