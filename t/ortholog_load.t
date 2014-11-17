use perl5i::2;

use Test::More tests => 9;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::Orthologs;

my $pub_uniquename = "PMID:19029536";

my @options = ("--publication=$pub_uniquename",
               "--organism_1_taxonid=4896",
               "--organism_2_taxonid=9606",
               "--add_org_1_term_name=predominantly single copy (one to one)",
               "--add_org_1_term_cv=species_dist",
               "--swap-direction");

my $rel_rs = $chado->resultset('Sequence::FeatureRelationship');
is($rel_rs->count(), 3);

my $importer = PomBase::Import::Orthologs->new(chado => $chado,
                                               config => $config,
                                               options => [@options]);

open my $fh, '<', "data/ortholog.tsv" or die;

my ($out, $err) = capture {
  my $load_count = $importer->load($fh);
  is ($load_count, 1);
};

like($err, qr|can't find feature in Chado for ENSG00000142544|);

$rel_rs = $chado->resultset('Sequence::FeatureRelationship');
is($rel_rs->count(), 4);

my $rel;

while (defined ($rel = $rel_rs->next())) {
  last if $rel->type()->name() eq 'orthologous_to';
}

my $pombe_feature = $rel->object();

my $one_to_one_term =
  $chado->resultset('Cv::Cvterm')->find({ name => 'predominantly single copy (one to one)' });
my $one_to_one_rs =
  $chado->resultset('Sequence::FeatureCvterm')
     ->search({ feature_id => $pombe_feature->feature_id(),
                cvterm_id => $one_to_one_term->cvterm_id() });
is($one_to_one_rs->count(), 1);

my $rel_pubs_rs = $rel->feature_relationship_pubs();
is($rel_pubs_rs->count(), 1);
is($rel_pubs_rs->first()->pub()->uniquename(), $pub_uniquename);

is($rel->subject()->organism()->common_name(), "human");
is($pombe_feature->organism()->common_name(), "pombe");

close $fh;
