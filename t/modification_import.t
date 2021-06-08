use strict;
use warnings;
use Carp;

use Capture::Tiny qw(capture);

use Test::More tests => 8;

use PomBase::TestUtil;
use PomBase::Import::Modification;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

my $importer =
  PomBase::Import::Modification->new(chado => $chado, config => $config);

my $feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm');
is($feature_cvterm_rs->count(), 7);

open my $fh, '<', "data/bulk_modification.tsv" or die;
my $res;

my ($out, $err) = capture {
  $res = $importer->load($fh);
};
if (length $out > 0) {
  fail $out;
}
if (length $err > 0) {
  fail $out;
}

$feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm');
is($feature_cvterm_rs->count(), 9);

my $spbc2f12_13_annotation_found = 0;
my $spac2f7_03c_annotation_found = 0;

while (defined (my $fc = $feature_cvterm_rs->next())) {
  if ($fc->cvterm()->name() eq 'protein modification categorized by amino acid modified') {
    if ($fc->feature()->uniquename() eq 'SPBC2F12.13.1') {
      $spbc2f12_13_annotation_found = 1;
      is($fc->pub()->uniquename(), "PMID:11739790");
      is($fc->feature_cvtermprops(), 3);
      my $rs = $fc->feature_cvtermprops()->search({ 'type.name' => 'evidence' },
                                                  { join => 'type' });
      my $evidence = $rs->first()->value();
      is($evidence, 'Inferred from Direct Assay');
    }
    if ($fc->feature()->uniquename() eq 'SPAC2F7.03c.1') {
      $spac2f7_03c_annotation_found = 1;
      is($fc->pub()->uniquename(), "PMID:11739790");
    }
  }
}

ok($spbc2f12_13_annotation_found);
ok($spac2f7_03c_annotation_found);

close $fh;
