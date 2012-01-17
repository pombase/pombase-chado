use strict;
use warnings;
use Test::More tests => 10;

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

my $expected_term_base =
  "PomBase	SPBC2F12.13.1		contributes_to	GO:0005816	" .
  "PMID:11739790	Inferred from Electronic Annotation	IEA		" .
  "C			spindle pole body	cellular_component	gene	" .
  "taxon:4896	20091023	PomBase	";

sub _check_res
{
  my $expected_term = shift;

  my $results = $retriever->retrieve();

  my $result_data;

  while (my $data = $results->next()) {
    if ($data->[4] eq 'GO:0005816') {
      $result_data = $data;
    }
  }

  is ($result_data->[12], 'spindle pole body');

  my $formatted_results = $retriever->format_result($result_data);
  is($formatted_results, $expected_term);
  is($retriever->header(), '');
}

{
  my $expected_term = $expected_term_base . "\t\n";

  _check_res($expected_term);
}

{
  # test exporting an annotation extension
  my $feat = $chado->resultset('Sequence::Feature')->find({ uniquename => 'SPBC2F12.13.1' });
  my $fcs = $feat->feature_cvterms();

  is($fcs->count(), 1);

  my $fc = $fcs->first();
  my $orig_cvterm = $fc->cvterm();

  is($orig_cvterm->name(), 'spindle pole body');

  my $ex_processor = PomBase::Chado::ExtensionProcessor->new(chado => $chado,
                                                             config => $config);

  $ex_processor->process_one_annotation($fc, 'has_substrate(GO:0051329)');

  my $new_cvterm = $feat->feature_cvterms()->first()->cvterm();

  is($new_cvterm->name(),
     'spindle pole body [has_substrate] interphase of mitotic cell cycle');

  my $parent_cvterm = PomBase::Retrieve::GeneAssociationFile::_get_base_term($new_cvterm);

  is($parent_cvterm->name(), 'spindle pole body');

  my $expected_term = $expected_term_base . "\t\n";

  _check_res($expected_term);
}
