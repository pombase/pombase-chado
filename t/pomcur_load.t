use perl5i::2;

use Test::More tests => 15;
use Test::Deep;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::PomCur;

my $annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 6);

my $feature_rs = $chado->resultset('Sequence::Feature');
is($feature_rs->count(), 19);


my $importer =
  PomBase::Import::PomCur->new(chado => $chado, config => $config);

open my $fh, '<', "data/pomcur_dump.json" or die;
$importer->load($fh);
close $fh;

$annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 12);

my $test_term_count = 0;

while (defined (my $fc = $annotations->next())) {
  my @props = $fc->feature_cvtermprops()->all();
  my %prop_hash = map { ($_->type()->name(), $_->value()); } @props;

  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1:allele-1' &&
      $fc->cvterm->name() eq
      'negative regulation of transmembrane transport [exists_during] interphase of mitotic cell cycle [has_substrate] SPBC1105.11c [requires_feature] Pfam:PF00564') {
    $test_term_count++;
    cmp_deeply(\%prop_hash,
               {
                 'date' => '2010-01-02',
                 'curator_email' => 'some.testperson@pombase.org',
                 'curator_name' => 'Some Testperson',
                 'community_curated' => 'false',
                 'residue' => 'T586(T586,X123)',
                 'evidence' => 'Inferred from Physical Interaction',
                 'assigned_by' => 'PomBase',
                 'with' => 'SPCC576.16c',
                 'condition' => 'PECO:0000012',
                 'curs_key' => 'aaaa0007',
               });
  }
  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1' &&
      $fc->cvterm()->name() eq 'transmembrane transporter activity') {
    $test_term_count++;
    cmp_deeply(\%prop_hash,
               {
                 'date' => '2010-01-02',
                 'evidence' => 'Inferred from Direct Assay',
                 'curator_email' => 'some.testperson@pombase.org',
                 'curator_name' => 'Some Testperson',
                 'community_curated' => 'false',
                 'assigned_by' => 'PomBase',
                 'curs_key' => 'aaaa0007',
               });
  }

  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1' &&
      $fc->cvterm()->name() eq 'negative regulation of transmembrane transport [exists_during] interphase of mitotic cell cycle [has_substrate] SPBC1105.11c') {
    $test_term_count++;
    cmp_deeply(\%prop_hash,
               {
                 'date' => '2010-01-02',
                 'evidence' => 'Inferred from Physical Interaction',
                 'curator_email' => 'some.testperson@pombase.org',
                 'curator_name' => 'Some Testperson',
                 'community_curated' => 'false',
                 'assigned_by' => 'PomBase',
                 'with' => 'SPCC576.16c',
                 'curs_key' => 'aaaa0007',
               });
  }
}

is($test_term_count, 3);

my $allele = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPAC27D7.13c:allele-2' });
ok(defined $allele);

is($allele->name(), 'ssm4-D4');
is($allele->search_featureprops('description')->first()->value(), 'del_100-200');

$feature_rs = $chado->resultset('Sequence::Feature');
is($feature_rs->count(), 21);

my @allele_cvterms = map { $_->cvterm(); } $allele->feature_cvterms();
is(@allele_cvterms, 1);
is($allele_cvterms[0]->name(), 'elongated cells');


my $interaction_gene = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPCC63.05' });
my $feature_rel_rs = $chado->resultset('Sequence::FeatureRelationship')
                           ->search({ subject_id => $interaction_gene->feature_id() });
is($feature_rel_rs->count(), 2);
cmp_deeply([sort map { $_->object()->uniquename() } $feature_rel_rs->all()],
           ['SPAC27D7.13c', 'SPBC14F5.07']);

