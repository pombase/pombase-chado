use perl5i::2;

use Test::More tests => 8;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::Orthologs;

my $pub_uniquename = "PMID:19029536";

my @options = ("--publication=$pub_uniquename",
               "--organism_1_taxonid=4896",
               "--organism_2_taxonid=9606",
               "--swap-direction");

my $rel_rs = $chado->resultset('Sequence::FeatureRelationship');
is($rel_rs->count(), 2);

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
is($rel_rs->count(), 3);

my $rel;

while (defined ($rel = $rel_rs->next())) {
  last if $rel->type()->name() eq 'orthologous_to';
}

my $rel_pubs_rs = $rel->feature_relationship_pubs();
is($rel_pubs_rs->count(), 1);
is($rel_pubs_rs->first()->pub()->uniquename(), $pub_uniquename);

is($rel->subject()->organism()->common_name(), "human");
is($rel->object()->organism()->common_name(), "pombe");

close $fh;
