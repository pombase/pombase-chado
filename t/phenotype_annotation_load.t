use perl5i::2;
use Test::More tests => 3;
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

my $annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 6);

open my $fh, '<', "data/phenotype_annotation.tsv" or die;
my $res = $importer->load($fh);

$annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 13);

while (defined (my $an = $annotations->next())) {
  if ($an->feature()->uniquename() eq 'SPAC2F7.03c:allele-2') {
    my %prop_hash = ();
    my @all_props = $an->feature_cvtermprops()->all();
    grep {
      push @{$prop_hash{$_->type()->name()}}, $_->value();
    } @all_props;

    cmp_deeply(\%prop_hash, {
            'penetrance' => [
              'FYPO_EXT:0000001'
            ],
            'expressivity' => [
              'FYPO_EXT:0000003',
            ],
            'date' => [
              '20130101'
            ],
            'evidence' => [
              'reporter gene assay evidence'
            ],
            'condition' => [
              'PECO:0000005',
              'PECO:0000081'
            ],
    });
  }
}

close $fh;
