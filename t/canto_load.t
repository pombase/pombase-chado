use perl5i::2;

use Test::More tests => 13;
use Test::Deep;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::Canto;

my $annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 7);

my $feature_rs = $chado->resultset('Sequence::Feature');
is($feature_rs->count(), 24);


my $importer =
  PomBase::Import::Canto->new(chado => $chado, config => $config,
                              options => [qw(--organism-taxonid=4896 --db-prefix=PomBase)]);

open my $fh, '<', "data/canto_dump.json" or die;
$importer->load($fh);
close $fh;

$annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 15);

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
                 'with' => 'PomBase:SPCC576.16c',
                 'condition' => 'PECO:0000012',
                 'canto_session' => 'aaaa0007',
                 'approved_timestamp' => '2014-10-07 02:51:14',
                 'approver_email' => 'val@sanger.ac.uk',
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
                 'canto_session' => 'aaaa0007',
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
                 'with' => 'PomBase:SPCC576.16c',
                 'canto_session' => 'aaaa0007',
               });
  }
}

is($test_term_count, 2);

$feature_rs = $chado->resultset('Sequence::Feature');
is($feature_rs->count(), 33);

my $genotype_1 = $chado->resultset('Sequence::Feature')
  ->find({ uniquename => 'aaaa0007-genotype-test-1' });

my @genotype_1_cvterms = map { $_->cvterm(); } $genotype_1->feature_cvterms();
is(@genotype_1_cvterms, 1);
is($genotype_1_cvterms[0]->name(), 'T-shaped cells');

my @genotype_1_alleles = $genotype_1->child_features();

is (scalar(@genotype_1_alleles), 2);

cmp_deeply(
  [sort {
    $a->{uniquename} cmp $b->{uniquename};
  } map {
    { uniquename => $_->uniquename(),
      name => $_->name() };
  } @genotype_1_alleles],
  [
    {
      'uniquename' => 'SPAC27D7.13c:allele-2',
      'name' => 'ssm4delta',
    },
    {
      'uniquename' => 'SPCC63.05:allele-1',
      'name' => 'SPCC63.05delta',
    }
  ]);

my $interaction_gene = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPCC63.05' });
my $feature_rel_rs = $chado->resultset('Sequence::FeatureRelationship')
                           ->search({ subject_id => $interaction_gene->feature_id() });
is($feature_rel_rs->count(), 2);
cmp_deeply([sort map { $_->object()->uniquename() } $feature_rel_rs->all()],
           ['SPAC27D7.13c', 'SPBC14F5.07']);

