use strict;
use warnings;
use Test::More tests => 25;

use PomBase::TestUtil;
use PomBase::Retrieve::Ontology;
use PomBase::Chado::ExtensionProcessor;

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

# test export of terms that have a parent in another ontology
my $feat = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPBC2F12.13.1' });
my $fcs = $feat->feature_cvterms();

is($fcs->count(), 2);

my $spindle_cvterm = $chado->resultset('Cv::Cvterm')->find({ name => 'spindle pole body' });
ok (defined $spindle_cvterm);

my $fc = $fcs->find({ cvterm_id => $spindle_cvterm->cvterm_id() });
ok (defined $fc);

my $ex_processor = PomBase::Chado::ExtensionProcessor->new(chado => $chado,
                                                           config => $config);

$ex_processor->process_one_annotation($fc, 'has_substrate(GO:0051329)');

my $fcs2 = $feat->feature_cvterms();
ok (defined $fcs2);

is($fc->cvterm()->name(), $spindle_cvterm->name() . ' [has_substrate] interphase of mitotic cell cycle');


my @options2 = ('--constraint-type', 'db_name',
                '--constraint-value', 'PomBase');
my $retriever2 = PomBase::Retrieve::Ontology->new(chado => $chado,
                                                  config => $config,
                                                  options => [@options2]);

my $results2 = $retriever2->retrieve();

my @parent_data = ();

while (defined (my $data = $results2->next())) {
  if ($data->[0] eq 'spindle pole body [has_substrate] interphase of mitotic cell cycle') {
    is($data->[4], 'spindle pole body'); # parent
    is($data->[5], 'GO');
    is($data->[6], '0005816');
  }
  if ($data->[0] eq 'spindle pole body') {
    @parent_data = @$data;
  }
}

is($parent_data[0], 'spindle pole body');
is($parent_data[1], 'cellular_component');
is($parent_data[2], 'GO');
is($parent_data[3], '0005816');

