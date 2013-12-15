use strict;
use warnings;
use Test::More tests => 3;

use PomBase::TestUtil;
use PomBase::Retrieve::PhenotypeAnnotationFormat;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

my $exporter = PomBase::Retrieve::PhenotypeAnnotationFormat->new(chado => $chado,
                                                                 config => $config,
                                                                 options => ['--organism-taxon-id' => 4896]);

is ($exporter->header(), '');

my $results = $exporter->retrieve();

ok(defined $results);

while (my $data = $results->next()) {
  is($exporter->format_result($data),
     join ("\t",
           (
             'SPAC27D7.13c',
             'FYPO:0000017',
             'SPAC27D7.13c',
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
}
