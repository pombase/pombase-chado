use strict;
use warnings;
use Test::More tests => 7;
use Test::LongString;
use Test::Deep;

use PomBase::TestUtil;
use PomBase::Retrieve::PhenotypeAnnotationFormat;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

my $exporter = PomBase::Retrieve::PhenotypeAnnotationFormat->new(chado => $chado,
                                                                 config => $config,
                                                                 options => ['--organism-taxon-id' => 4896]);

my %allele_gene_map_res = $exporter->_get_allele_gene_map();

cmp_deeply(\%allele_gene_map_res,
           {
             'SPAC27D7.13c:allele-1' => {
               gene_uniquename => 'SPAC27D7.13c',
               gene_name => 'ssm4',
             }
           });

my %allele_props_res = $exporter->_get_allele_props();

cmp_deeply(\%allele_props_res,
           {
             'SPAC27D7.13c:allele-1' => {
               allele_type => 'nucleotide_mutation',
               description => 'A123T',
             }
           });

my $genotype_rs = $chado->resultset('Sequence::Feature')
  ->search({ 'type.name' => 'genotype' }, { join => 'type' });

my %genotype_details = $exporter->_get_genotype_details($genotype_rs);

cmp_deeply(\%genotype_details,
           {
            'aaaa0007-genotype-1' => [
                                       {
                                         'gene_uniquename' => 'SPAC27D7.13c',
                                         'allele_type' => 'nucleotide_mutation',
                                         'gene_name' => 'ssm4',
                                         'allele_uniquename' => 'SPAC27D7.13c:allele-1',
                                         'description' => 'A123T',
                                         'allele_name' => 'ssm4-m1',
                                         'expression' => 'Knockdown'
                                       },
                                     ],
           });

is_string ($exporter->header(), "#Database name\tGene systematic ID\tFYPO ID\tAllele description\tExpression\tParental strain\tStrain name (background)\tGenotype description\tGene name\tAllele name\tAllele synonym\tAllele type\tEvidence\tCondition\tPenetrance\tSeverity\tExtension\tReference\tTaxon\tDate\n");

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
             'A123T',
             'Knockdown',
             '972 h-',
             '',
             '',
             'ssm4',
             'ssm4-m1',
             '',
             'nucleotide_mutation',
             'Co-immunoprecipitation experiment',
             'FYECO:0000005',
             'FYPO_EXT:0000003',
             '',
             '',
             'PMID:11739790',
             4896,
             '20091020'
           )));

  $count++;
}

is($count, 1);
