use perl5i::2;

use Test::More tests => 7;

use PomBase::TestUtil;

my $test_util = PomBase::TestUtil->new();
my $chado = $test_util->chado();
my $config = $test_util->config();

use PomBase::Import::BioGRID;

my $pub_uniquename = "PMID:19029536";

my @options = (
  "--organism-taxonid-filter=4896:4896",
  "--interaction-note-filter=Contributed by PomBase|contributed by PomBase|triple mutant",
  "--evidence-code-filter=Co-localization");

my $rel_rs = $chado->resultset('Sequence::FeatureRelationship');
is($rel_rs->count(), 9);

my $importer = PomBase::Import::BioGRID->new(chado => $chado,
                                             config => $config,
                                             options => [@options]);

open my $fh, '<', "data/biogrid-pombe-small" or die;

my ($out, $err) = capture {
  $importer->load($fh);
};

fail "Message from importer: $out" if $out;
fail "Error from importer: $err" if $err;

$rel_rs = $chado->resultset('Sequence::FeatureRelationship');
is($rel_rs->count(), 15);

my $SPAC1093_06c_count = 0;
my $SPCC576_16c_count = 0;
my $saw_SPCC63_05_reciprocal = 0;

while (defined (my $rel = $rel_rs->next())) {
  if ($rel->subject()->uniquename() eq 'SPAC1093.06c') {
    is ($rel->object()->uniquename(), 'SPCC576.16c');
    $SPAC1093_06c_count++;
  }
  if ($rel->subject()->uniquename() eq 'SPAC2F7.03c') {
    is ($rel->object()->uniquename(), 'SPCC63.05');
    $SPCC576_16c_count++;
  }

  if ($rel->subject()->uniquename() eq 'SPCC576.16c' && $rel->object()->uniquename() eq 'SPCC63.05') {
    $saw_SPCC63_05_reciprocal = 1;

    ok (grep {
      $_->type()->name() eq 'evidence' and $_->value() eq 'Positive Genetic';
    } $rel->feature_relationshipprops()->all());
  }
}


# check that duplicate is removed for non-symmetrical interaction
is ($SPAC1093_06c_count, 1);

# check that duplicate is removed for symmetrical interaction
is ($SPCC576_16c_count, 1);

fail "no SPCC63.05 reciprocal" unless $saw_SPCC63_05_reciprocal;

close $fh;
