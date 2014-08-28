use perl5i::2;

use Test::More tests => 7;
use Test::Deep;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

$config->{systematic_id_re} = 'SP.[CP]\w+\d+\w+\d+c?.\d';
$config->{organism_taxon_map} = {
  284812 => 4896,
};

use PomBase::Import::GeneAssociationFile;

my @options = ("--assigned-by-filter=UniProtKB,InterPro,IntAct,Reactome",
               "--remove-existing");

my $importer;

my ($out, $err) = capture {
  $importer =
    PomBase::Import::GeneAssociationFile->new(chado => $chado,
                                              config => $config,
                                              options => [@options]);
};

is ($err, "no taxon filter - annotation will be loaded for all taxa\n");

open my $fh, '<', "data/gene_association.goa.small" or die;
my $deleted_counts = $importer->load($fh);
cmp_deeply($deleted_counts,
           {
             IntAct => 0,
             InterPro => 0,
             Reactome => 0,
             UniProtKB => 0,
           });
my $annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 15);
close $fh;

# make sure we can re-load, existing data should be deleted
open $fh, '<', "data/gene_association.goa.small" or die;
$deleted_counts = $importer->load($fh);
cmp_deeply($deleted_counts,
           {
             IntAct => 1,
             InterPro => 2,
             Reactome => 1,
             UniProtKB => 4,
           });
$annotations = $chado->resultset('Sequence::FeatureCvterm');
is($annotations->count(), 15);

while (defined (my $fc = $annotations->next())) {
  my @props = $fc->feature_cvtermprops()->all();

  if ($fc->feature->uniquename() eq 'SPAC1093.06c.1') {
    ok (grep { $_->type()->name() eq 'with' &&
               $_->value() eq 'InterPro:IPR004273' } @props);
  }

  if ($fc->feature()->uniquename() eq 'SPBC2F12.13.1') {
    if (grep { $_->type()->name() eq 'date' &&
               $_->value() eq '20110721' } @props) {
      ok (grep { $_->type()->name() eq 'with' &&
                   $_->value() eq 'PomBase:SPBC2F12.13' } @props);
    }
  }
}

close $fh;
