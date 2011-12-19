use perl5i::2;

use Test::More tests => 4;
use Test::Deep;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::PomCur;

my $annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 1);

my $importer =
  PomBase::Import::PomCur->new(chado => $chado, config => $config);

open my $fh, '<', "data/pomcur_dump.json" or die;
$importer->load($fh);
close $fh;

$annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 5);

while (defined (my $fc = $annotations->next())) {
  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1') {
    is ($fc->cvterm->name(),
        'negative regulation of transmembrane transport');

    my @props = $fc->feature_cvtermprops()->all();
    ok (grep { $_->type()->name() eq 'with' &&
               $_->value() eq 'SPCC576.16c' } @props);
  }
}
