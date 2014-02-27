use strict;
use warnings;
use Test::More tests => 4;
use Test::LongString;

use PomBase::TestUtil;
use PomBase::Retrieve::PhenotypeAnnotationFormat;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

my $exporter = PomBase::Retrieve::PhenotypeAnnotationFormat->new(chado => $chado,
                                                                 config => $config,
                                                                 options => ['--organism-taxon-id' => 4896]);

is_string ($exporter->header(), "#Database name\tGene systematic ID\tFYPO ID\tAllele description\tExpression\tParental strain\tStrain name (background)\tGenotype description\tGene name\tAllele name\tAllele synonym\tAllele type\tEvidence\tCondition\tPenetrance\tExpressivity\tExtension\tReference\tTaxon\tDate\n");

my $results = $exporter->retrieve();

ok(defined $results);

my $count = 0;

while (my $data = $results->next()) {
  is_string($exporter->format_result($data),
     join ("\t",
           (
             'PomBase',
             'SPAC27D7.13c',
             'FYPO:0000017',
             '',
             '',
             '972 h-',
             'not available',
             'not available',
             'SPAC27D7.13c',
             '',
             '',
             'nucleotide_mutation',
             'Co-immunoprecipitation experiment',
             'PECO:0000005',
             'FYPO_EXT:0000001',
             '',
             '',
             'PMID:11739790',
             4896,
             '20091020'
           )));

  $count++;
}

is($count, 1);
