use strict;
use warnings;
use Test::More tests => 3;

use Test::Deep;

use PomBase::TestUtil;
use PomBase::Retrieve::GeneAssociationFile;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

my $retriever = PomBase::Retrieve::GeneAssociationFile->new(chado => $chado,
                                                            config => $config,
                                                            options => [ '--organism-taxon-id' => 4896 ]);

my $results = $retriever->retrieve();

my $expected_term =
  "PomBase	SPBC2F12.13.1		QUALIFIER	GO:0005816	" .
  "PMID:11739790	Inferred from Electronic Annotation	IEA		" .
  "C			spindle pole body	cellular_component	gene	" .
  "taxon:4896	20091023	PomBase	ANNOTATION_EXTENSION	\n";

while (my $data = $results->next()) {
  if ($data->[4] eq 'GO:0005816') {
    is ($data->[12], 'spindle pole body');

    my $formatted_results = $retriever->format_result($data);

    is($formatted_results, $expected_term);
  }
}

is($retriever->header(), '');
