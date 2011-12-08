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
                                                            config => $config);

my $results = $retriever->retrieve();

my $expected_term = "spindle pole body	GO:0005816
";

while (my $data = $results->next()) {
  if ($data->[0] eq 'spindle pole body') {
    is($data->[1], 'GO:0005816');

    my $formatted_results = $retriever->format_result($data);

    is($formatted_results, $expected_term);
  }
}

is($retriever->header(), '');
