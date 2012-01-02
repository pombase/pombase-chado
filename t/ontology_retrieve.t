use strict;
use warnings;
use Test::More tests => 9;

use PomBase::TestUtil;
use PomBase::Retrieve::Ontology;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

my @options = ('--constraint-type', 'db_name',
               '--constraint-value', 'GO');
my $retriever = PomBase::Retrieve::Ontology->new(chado => $chado,
                                                 config => $config,
                                                 options => [@options]);

my $results = $retriever->retrieve();

my $expected_term = "[Term]
id: GO:0003777
name: microtubule motor activity
namespace: molecular_function
is_a: GO:0003674

";
my $expected_parent = "[Term]
id: GO:0003674
name: molecular_function
namespace: molecular_function

";

while (my $data = $results->next()) {
  if ($data->[0] eq 'microtubule motor activity') {
    is($data->[1], 'molecular_function');
    is($data->[2], 'GO');
    is($data->[3], '0003777');

    my $formatted_results = $retriever->format_result($data);

    is($formatted_results, $expected_term);
  }
  if ($data->[0] eq 'molecular_function') {
    is($data->[1], 'molecular_function');
    is($data->[2], 'GO');
    is($data->[3], '0003674');

    my $formatted_results = $retriever->format_result($data);

    is($formatted_results, $expected_parent);
  }
}

my $expected_header = 'format-version: 1.2
ontology: pombase
default-namespace: pombase
';

is($retriever->header(), $expected_header);
