use perl5i::2;
use Test::More tests => 9;
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
  fail $err;
}

$feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm');
is($feature_cvterm_rs->count(), 14);

my $found_PomBase_genotype_2 = 0;
my $found_PomBase_genotype_5_expression = 0;

while (defined (my $fc = $feature_cvterm_rs->next())) {
  my $feature = $fc->feature();
  my $cvterm = $fc->cvterm();

  if ($feature->uniquename() eq 'PomBase-genotype-2') {
    $found_PomBase_genotype_2 = 1;

    is ($cvterm->name(), "T-shaped cells [has_expressivity] low [has_penetrance] high");

    my %prop_hash = ();
    my @all_props = $fc->feature_cvtermprops()->all();
    grep {
      push @{$prop_hash{$_->type()->name()}}, $_->value();
    } @all_props;

    cmp_deeply(\%prop_hash, {
            'date' => [
              '2013-01-01'
            ],
            'evidence' => [
              'reporter gene assay evidence'
            ],
            'condition' => [
              'PECO:0000005',
              'PECO:0000081'
            ]
    });

    my $rel = $feature->feature_relationship_objects()->first();
    my $allele = $rel->subject();

    my $alleleprop_rs = $allele->featureprops();

    my %alleleprops = ();
    my @all_alleleprops = $alleleprop_rs->all();
    grep {
      push @{$alleleprops{$_->type()->name()}}, $_->value();
    } @all_alleleprops;

    cmp_deeply(\%alleleprops, {
      'allele_type' => [
        'amino_acid_mutation'
      ],
      'description' => [
        'A10T'
      ],
    });
  } else {
    if ($feature->uniquename() eq 'PomBase-genotype-5') {
      for my $rel ($feature->feature_relationship_objects()->all()) {
        for my $prop ($rel->feature_relationshipprops()) {
          if ($prop->type()->name() eq 'expression' &&
                $prop->value() eq 'Overexpression') {
            $found_PomBase_genotype_5_expression = 1;
          }
        }
      }
    }
  }
}

ok($found_PomBase_genotype_2);
ok($found_PomBase_genotype_5_expression);

my $feature_rs = $chado->resultset('Sequence::Feature');

while (defined (my $feature = $feature_rs->next())) {
  if ($feature->uniquename() eq 'SPBC2F12.13:allele-1') {
    is ($feature->name(), 'klp5delta');
  }

  if ($feature->uniquename() eq 'SPAC1093.06c:allele-2') {
    is ($feature->name(), 'SPAC1093.06c+');
  }
}

close $fh;
