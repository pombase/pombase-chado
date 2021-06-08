use strict;
use warnings;
use Test::More tests => 6;
use strict;
use warnings;
use Carp;

use Capture::Tiny qw(capture);

use PomBase::TestUtil;
use PomBase::Chado::ChangeTerms;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

sub has_annotation
{
  my $term_name = shift;
  my $uniquename = shift;


  my $rs = $chado->resultset("Sequence::FeatureCvterm")->
    search({ 'cvterm.name' => $term_name,
             'feature.uniquename' => $uniquename, },
           { join => [qw(cvterm feature)] });

  return $rs->count() == 1;
}

ok (has_annotation('spindle pole body', 'SPBC2F12.13.1'));
ok (!has_annotation('molecular_function', 'SPBC2F12.13.1'));

my $change_terms =
  PomBase::Chado::ChangeTerms->new(chado => $chado,
                                   config => $config,
                                   options => [qw(--mapping-file data/change_terms_mapping_example.txt)]);

my ($out, $err) = capture {
  $change_terms->process();
};

is ($out, '');
is ($err, "These term changes aren't possible because a duplicate would result:
  PMID:11739790 - SPAC2F7.03c.1  GO:0005816(spindle pole body) -> GO:0003674(molecular_function)
");

ok (!has_annotation('spindle pole body', 'SPBC2F12.13.1'));
ok (has_annotation('molecular_function', 'SPBC2F12.13.1'));

