use perl5i::2;

use Test::More tests => 14;
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
is($annotations->count(), 13);

my $test_term_count = 0;

while (defined (my $fc = $annotations->next())) {
  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1:allele-1' &&
      $fc->cvterm->name() eq
      'negative regulation of transmembrane transport [exists_during] interphase of mitotic cell cycle [has_substrate] SPBC1105.11c [requires_feature] Pfam:PF00564') {
    my @props = $fc->feature_cvtermprops()->all();
    my %prop_hash = map { ($_->type()->name(), $_->value()); } @props;
    $test_term_count++;
    cmp_deeply(\%prop_hash,
               {
                 'date' => '2010-01-02',
                 'curator' => 'Ken.Sawin@ed.ac.uk',
                 'residue' => 'T586(T586,X123)',
                 'qualifier' => 'NOT',
                 'evidence' => 'Inferred from Physical Interaction',
                 'assigned_by' => 'PomBase',
                 'with' => 'SPCC576.16c',
                 'condition' => 'PCO:0000012'
               });
  }
  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1' &&
      $fc->cvterm()->name() eq 'transmembrane transporter activity') {
    my @props = $fc->feature_cvtermprops()->all();
    my %prop_hash = map { ($_->type()->name(), $_->value()); } @props;
    $test_term_count++;
    cmp_deeply(\%prop_hash,
               {
                 'date' => '2010-01-02',
                 'evidence' => 'Inferred from Direct Assay',
                 'curator' => 'Ken.Sawin@ed.ac.uk',
                 'assigned_by' => 'PomBase'
               });
  }
}

is($test_term_count, 2);

my $allele = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPAC27D7.13c:allele-2' });
ok(defined $allele);

is($allele->name(), 'ssm4-D4');
is($allele->search_featureprops('description')->first()->value(), 'del_100-200');

$feature_rs = $chado->resultset('Sequence::Feature');
is($feature_rs->count(), 17);

my @allele_cvterms = map { $_->cvterm(); } $allele->feature_cvterms();
is(@allele_cvterms, 1);
is($allele_cvterms[0]->name(), 'elongated cells');


my $interaction_gene = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPCC63.05' });
my $feature_rel_rs = $chado->resultset('Sequence::FeatureRelationship')
                           ->search({ subject_id => $interaction_gene->feature_id() });
is($feature_rel_rs->count(), 2);
cmp_deeply([sort map { $_->object()->uniquename() } $feature_rel_rs->all()],
           ['SPAC27D7.13c', 'SPBC14F5.07']);

