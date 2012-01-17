use strict;
use warnings;
use Test::More tests => 14;

use Test::Deep;

use PomBase::TestUtil;
use PomBase::Retrieve::GeneAssociationFile;
use PomBase::Chado::ExtensionProcessor;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

my $retriever = PomBase::Retrieve::GeneAssociationFile->new(chado => $chado,
                                                            config => $config,
                                                            options => [ '--organism-taxon-id' => 4896 ]);

my $expected_term_0005816_base =
  "PomBase\tSPBC2F12.13.1\t\t\tGO:0005816\t" .
  "PMID:11739790\tInferred from Electronic Annotation\tIEA\t\t" .
  "C\t\t\tspindle pole body\tcellular_component\tgene\t" .
  "taxon:4896\t20091023\tPomBase\t";

sub _check_res
{
  my $expected_term_0005816 = shift;

  my $results = $retriever->retrieve();

  my $result_data_0005816;
  my $result_data_0051329;

  while (my $data = $results->next()) {
    if ($data->[4] eq 'GO:0005816') {
      die if defined $result_data_0005816;
      $result_data_0005816 = $data;
    } else {
      if ($data->[4] eq 'GO:0051329') {
        die if defined $result_data_0051329;
        $result_data_0051329 = $data;
      } else {
        fail("unexpected row");
      }
    }
  }

  is ($result_data_0005816->[12], 'spindle pole body');
  is ($result_data_0051329->[12], 'interphase of mitotic cell cycle');

  {
    my $formatted_results = $retriever->format_result($result_data_0005816);
    is($formatted_results, $expected_term_0005816);
  }
  is($retriever->format_result($result_data_0051329),
     "PomBase\tSPBC2F12.13.1\t\tcontributes_to|NOT\tGO:0051329\tPMID:11739790\tInferred from Direct Assay\tIDA\t\tP\t\t\tinterphase of mitotic cell cycle\tbiological_process\tgene\ttaxon:4896\t20091020\tPomBase\t\t\n");

  is($retriever->header(), '');
}

{
  my $expected_term_0005816 = $expected_term_0005816_base . "\t\n";
  _check_res($expected_term_0005816);
}

{
  # test exporting an annotation extension
  my $feat = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPBC2F12.13.1' });
  my $fcs = $feat->feature_cvterms();

  is($fcs->count(), 2);

  my $spindle_pb_cvterm = $chado->resultset('Cv::Cvterm')->find({ name => 'spindle pole body' });

  my $fc = $fcs->search({ cvterm_id => $spindle_pb_cvterm->cvterm_id() })->first();
  my $orig_cvterm = $fc->cvterm();

  is($orig_cvterm->name(), 'spindle pole body');

  my $ex_processor = PomBase::Chado::ExtensionProcessor->new(chado => $chado,
                                                             config => $config);

  $ex_processor->process_one_annotation($fc, 'has_substrate(GO:0051329)');

  my $ex_cvterm = $chado->resultset('Cv::Cvterm')->find({ name =>
     'spindle pole body [has_substrate] interphase of mitotic cell cycle' });

  ok (defined $ex_cvterm);

  my $parent_cvterm = PomBase::Retrieve::GeneAssociationFile::_get_base_term($ex_cvterm);

  is($parent_cvterm->name(), 'spindle pole body');

  my $expected_term_0005816 = $expected_term_0005816_base . "\t\n";

  _check_res($expected_term_0005816);
}
