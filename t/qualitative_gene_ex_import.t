use strict;
use warnings;
use Carp;

use Test::More tests => 8;

use PomBase::TestUtil;
use PomBase::Import::Qualitative;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

$config->{gene_ex_qualifiers} =
  [qw(decreased absent increased present unchanged constant fluctuates)];

my $importer =
  PomBase::Import::Qualitative->new(chado => $chado, config => $config);

my $feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm');
is($feature_cvterm_rs->count(), 7);

open my $fh, '<', "data/bulk_qualitative_gene_ex.tsv" or die;
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
  if ($fc->cvterm()->name() eq 'protein level' &&
      $fc->feature()->uniquename() eq 'SPBC2F12.13') {
    $spbc2f12_13_annotation_found = 1;
    is($fc->pub()->uniquename(), "PMID:11739790");
    is($fc->feature_cvtermprops(), 3);
    my $rs = $fc->feature_cvtermprops()->search({ 'type.name' => 'evidence' },
                                                {
                                                  join => 'type' });
    my $evidence = $rs->first()->value();
    is($evidence, 'mass spectrometry evidence');
  }
  if ($fc->cvterm()->name() eq 'protein level [during] transmembrane transport' &&
      $fc->feature()->uniquename() eq 'SPAC2F7.03c') {
    $spac2f7_03c_annotation_found = 1;
    is($fc->pub()->uniquename(), "PMID:11739790");
  }
}

ok($spbc2f12_13_annotation_found);
ok($spac2f7_03c_annotation_found);

close $fh;
