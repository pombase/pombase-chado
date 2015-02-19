use perl5i::2;
use Test::More tests => 11;
use Test::Deep;

use PomBase::TestUtil;
use PomBase::Import::PhenotypeAnnotation;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

my @options = ();

my $importer =
  PomBase::Import::PhenotypeAnnotation->new(chado => $chado,
                                            config => $config,
                                            options => [@options]);

my $feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm');
is($feature_cvterm_rs->count(), 7);

open my $fh, '<', "data/phenotype_annotation.tsv" or die;
my $res;

my ($out, $err) = capture {
  $res = $importer->load($fh);
};
if (length $out > 0) {
  fail $out;
}
if (length $err > 0) {
  like($err, qr/gene name from phenotype annotation file \("gene1"\) doesn't match the existing name \(""\) for SPAC2F7.03c/);
}

$feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm');
is($feature_cvterm_rs->count(), 14);

my $found_SPAC2F7_03c_allele_2 = 0;

while (defined (my $fc = $feature_cvterm_rs->next())) {
  my $feature = $fc->feature();

  if ($feature->uniquename() eq 'SPAC2F7.03c:allele-2') {
    my $cvterm = $fc->cvterm();

    $found_SPAC2F7_03c_allele_2 = 1;

    is ($cvterm->name(), "T-shaped cells [has_expressivity] low [has_penetrance] high");

    my %prop_hash = ();
    my @all_props = $fc->feature_cvtermprops()->all();
    grep {
      push @{$prop_hash{$_->type()->name()}}, $_->value();
    } @all_props;

    cmp_deeply(\%prop_hash, {
            'date' => [
              '20130101'
            ],
            'evidence' => [
              'ECO:0000049'
            ],
            'condition' => [
              'PECO:0000005',
              'PECO:0000081'
            ],
    });

    my $featureprop_rs = $feature->featureprops();

    my %featureprops = ();
    my @all_featureprops = $featureprop_rs->all();
    grep {
      push @{$featureprops{$_->type()->name()}}, $_->value();
    } @all_featureprops;

    cmp_deeply(\%featureprops, {
      'allele_type' => [
        'amino_acid_mutation'
      ],
      'description' => [
        'A10T'
      ],
    });
  } else {
    if ($feature->uniquename() eq 'SPBC2F12.13:allele-1') {
      is ($feature->name(), 'klp5delta');
    }

    if ($feature->uniquename() eq 'SPAC1093.06c:allele-2') {
      is ($feature->name(), 'SPAC1093.06c+');
    }
  }
}

ok($found_SPAC2F7_03c_allele_2);

close $fh;
