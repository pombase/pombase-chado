use perl5i::2;

use Test::More tests => 5;
use Test::Deep;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::GeneAssociationFile;

my @options = ("--assigned-by-filter=UniProtKB,InterPro,IntAct,Reactome",
               "--remove-existing");

my $importer =
  PomBase::Import::GeneAssociationFile->new(chado => $chado,
                                            config => $config,
                                            options => [@options]);

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
is($annotations->count(), 14);
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
is($annotations->count(), 14);

while (defined (my $fc = $annotations->next())) {
  if ($fc->feature->uniquename() eq 'SPAC1093.06c.1') {
    my @props = $fc->feature_cvtermprops()->all();
    ok (grep { $_->type()->name() eq 'with' &&
               $_->value() eq 'InterPro:IPR004273' } @props);
  }
}

close $fh;
