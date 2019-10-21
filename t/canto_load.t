use perl5i::2;

use Test::More tests => 22;
use Test::Deep;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::Canto;
use PomBase::Chado::GenotypeCache;

my $annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 7);

my $feature_rs = $chado->resultset('Sequence::Feature');
is($feature_rs->count(), 27);

my $genotype_cache = PomBase::Chado::GenotypeCache->new(chado => $chado);

my $importer =
  PomBase::Import::Canto->new(chado => $chado, config => $config,
                              genotype_cache => $genotype_cache,
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

  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1' &&
      $fc->cvterm->name() eq
      'negative regulation of transmembrane transport [exists_during] interphase of mitotic cell cycle [has_substrate] SPBC1105.11c') {
    $test_term_count++;
    cmp_deeply(\%prop_hash,
               {
                 'date' => '2010-01-04',
                 'curator_email' => 'some.testperson@3926fef56bb23eb871ee91dc2e3fdd7c46ef1385.org',
                 'curator_name' => 'Some Testperson',
                 'community_curated' => 'false',
                 'evidence' => 'Inferred from Physical Interaction',
                 'assigned_by' => 'PomBase',
                 'with' => 'PomBase:SPBC1826.01c',
                 'canto_session' => 'aaaa0007',
                 'annotation_throughput_type' => 'low throughput',
               });
  }
  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1' &&
      $fc->cvterm()->name() eq 'transmembrane transporter activity') {
    $test_term_count++;
    cmp_deeply(\%prop_hash,
               {
                 'date' => '2010-01-05',
                 'evidence' => 'Inferred from Direct Assay',
                 'curator_email' => 'some.testperson@3926fef56bb23eb871ee91dc2e3fdd7c46ef1385.org',
                 'curator_name' => 'Some Testperson',
                 'community_curated' => 'false',
                 'assigned_by' => 'PomBase',
                 'canto_session' => 'aaaa0007',
                 'annotation_throughput_type' => 'low throughput',
               });
  }

  if ($fc->feature->uniquename() eq 'SPBC14F5.07.1' &&
      $fc->cvterm()->name() eq 'negative regulation of transmembrane transport [exists_during] interphase of mitotic cell cycle [has_substrate] SPBC1105.11c') {
    $test_term_count++;
    cmp_deeply(\%prop_hash,
               {
                 'date' => '2010-01-04',
                 'evidence' => 'Inferred from Physical Interaction',
                 'curator_email' => 'some.testperson@3926fef56bb23eb871ee91dc2e3fdd7c46ef1385.org',
                 'curator_name' => 'Some Testperson',
                 'community_curated' => 'false',
                 'assigned_by' => 'PomBase',
                 'with' => 'PomBase:SPBC1826.01c',
                 'canto_session' => 'aaaa0007',
                 'annotation_throughput_type' => 'low throughput',
               });
  }
}

is($test_term_count, 3);

$feature_rs = $chado->resultset('Sequence::Feature');
is($feature_rs->count(), 41);

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



my $genetic_interaction =
  $chado->resultset('Sequence::Feature')->find({ uniquename => 'aaaa0007-genetic_interaction-metagenotype-1' });

is($genetic_interaction->type()->name(), 'genetic_interaction');

my $genetic_interaction_fc_rs = $genetic_interaction->feature_cvterms();

is ($genetic_interaction_fc_rs->count(), 1);

my $genetic_interaction_fc = $genetic_interaction_fc_rs->first();
is ($genetic_interaction_fc->cvterm()->name(), "elongated cells");

my $gi_fc_props_rs = $genetic_interaction_fc->feature_cvtermprops();

my %gi_props = ();

while (defined (my $prop = $gi_fc_props_rs->next())) {
  $gi_props{$prop->type()->name()} = $prop->value();
}

cmp_deeply(\%gi_props,
           {
             annotation_throughput_type => "low throughput",
             assigned_by => "PomBase",
             evidence => "Synthetic Haploinsufficiency",
             curator_name => "Some Testperson",
             curator_email => "some.testperson@3926fef56bb23eb871ee91dc2e3fdd7c46ef1385.org",
             community_curated => "false",
             canto_session => "aaaa0007",
             date => "2010-01-09",
           });


my $physical_interaction =
  $chado->resultset('Sequence::Feature')->find({ uniquename => 'aaaa0007-physical_interaction-metagenotype-2' });

is($physical_interaction->type()->name(), 'physical_interaction');

my $physical_interaction_fc_rs = $physical_interaction->feature_cvterms();
is ($physical_interaction_fc_rs->count(), 0);


my $genetic_rel_rs = $chado->resultset('Sequence::FeatureRelationship')
                           ->search({ object_id => $genetic_interaction->feature_id() });
is($genetic_rel_rs->count(), 2);
cmp_deeply([sort map { $_->subject()->uniquename() } $genetic_rel_rs->all()],
           ['aaaa0007-genotype-3', 'aaaa0007-genotype-4']);

my $physical_rel_rs = $chado->resultset('Sequence::FeatureRelationship')
                           ->search({ object_id => $physical_interaction->feature_id() });
is($physical_rel_rs->count(), 2);
cmp_deeply([sort map { $_->subject()->uniquename() } $physical_rel_rs->all()],
           ['aaaa0007-genotype-5', 'aaaa0007-genotype-6']);

