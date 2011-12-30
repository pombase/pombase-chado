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
is($annotations->count(), 6);

while (defined (my $fc = $annotations->next())) {
  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1') {
    if ($fc->cvterm->name() eq
'negative regulation of transmembrane transport [exists_during] GO:0051329 [has_substrate] SPBC1105.11c [requires_feature] Pfam:PF00564') {
      my @props = $fc->feature_cvtermprops()->all();
      my %prop_hash = map { ($_->type()->name(), $_->value()); } @props;
      cmp_deeply(\%prop_hash,
                 {
                   assigned_by => 'PomBase',
                   evidence => 'Inferred from Physical Interaction',
                   with => 'SPCC576.16c',
                 });
    } else {
      if ($fc->cvterm()->name() eq 'transmembrane transporter activity') {
        my @props = $fc->feature_cvtermprops()->all();
        my %prop_hash = map { ($_->type()->name(), $_->value()); } @props;
        cmp_deeply(\%prop_hash,
                   {
                     assigned_by => 'PomBase',
                     evidence => 'Inferred from Direct Assay',
                   });
      } else {
        fail("unexpected term: " . $fc->cvterm->name());
      }
    }
  }
}
