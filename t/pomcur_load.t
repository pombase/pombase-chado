use perl5i::2;

use Test::More tests => 5;
use Test::Deep;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::PomCur;

my $annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 6);

my $feature_rs = $chado->resultset('Sequence::Feature');
is($feature_rs->count(), 15);


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
'negative regulation of transmembrane transport [exists_during] interphase of mitotic cell cycle [has_substrate] SPBC1105.11c [requires_feature] Pfam:PF00564') {
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
        if ($fc->cvterm()->name() ne 'negative regulation of transmembrane transport') {
          fail("unexpected term: " . $fc->cvterm->name());
        }
      }
    }
  }
}

my $allele = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPAC27D7.13c:allele-2' });
ok(defined $allele);

is($allele->name(), 'ssm4-D4');
is($allele->search_featureprops('description')->first()->value(), 'del_100-200');

$feature_rs = $chado->resultset('Sequence::Feature');
is($feature_rs->count(), 16);

