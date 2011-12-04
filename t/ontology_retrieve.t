use strict;
use warnings;
use Test::More tests => 4;

#use File::Temp qw(tempfile);
#use File::Compare;

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

while (my $data = $results->next()) {
  if ($data->[0] eq 'microtubule motor activity') {
    is($data->[1], 'molecular_function');
    is($data->[2], 'GO');
    is($data->[3], '0003777');

    my $formatted_results = $retriever->format_result($data);

    my $expected = "[Term]
id: GO:0003777
name: microtubule motor activity
namespace: molecular_function
";

    is($formatted_results, $expected);
  }
}
