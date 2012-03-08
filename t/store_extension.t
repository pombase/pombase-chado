use perl5i::2;

use Test::More tests => 4;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::ExtensionProcessor;

my $fc_rs = $chado->resultset('Sequence::FeatureCvterm');

my $spindle_fc;

while (defined (my $fc = $fc_rs->next())) {
  if ($fc->cvterm()->name() eq 'spindle pole body') {
    $spindle_fc = $fc;
  }
}

my $extensions = [
  {
    'identifier' => 'Pfam:PF00069',
    'rel_name' => 'dependent_on',
  },
];

my $ex_processor = PomBase::Import::ExtensionProcessor->new(verbose => 0);

$ex_processor->store_extension($spindle_fc, $extensions);
