use strict;
use warnings;
use Test::More tests => 1;

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
  use Data::Dumper;
$Data::Dumper::Maxdepth = 3;
warn Dumper([$data]);

  warn $exporter->format_result($data), "\n";
}
