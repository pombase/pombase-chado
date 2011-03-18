#!/usr/bin/perl -w

use strict;
use warnings;
use Carp;

use Bio::SeqIO;
use Bio::Chado::Schema;
use Memoize;

my $verbose = 0;

if (@ARGV && $ARGV[0] eq '-v') {
  shift;
  $verbose = 1;
}

my $chado = Bio::Chado::Schema->connect('dbi:Pg:database=pombe-kmr-qual-dev',
                                        'kmr44', 'kmr44');

my $guard = $chado->txn_scope_guard;

my $cv_rs = $chado->resultset('Cv::Cv');

my $genedb_literature_cv = $cv_rs->find({ name => 'genedb_literature' });
my $phenotype_cv = $cv_rs->create({ name => 'phenotype' });

my $cvterm_rs = $chado->resultset('Cv::Cvterm');

my $unfetched_pub_cvterm = $cvterm_rs->find({ name => 'unfetched',
                                              cv_id => $genedb_literature_cv->cv_id() });

my %pombase_dbs = ();

$pombase_dbs{phenotype} =
  $chado->resultset('General::Db')->create({ name => 'PomBase phenotype' });

sub _dump_feature {
  my $feature = shift;

  for my $tag ($feature->get_all_tags) {
    print "  tag: ", $tag, "\n";
    for my $value ($feature->get_tag_values($tag)) {
      print "    value: ", $value, "\n";
    }
  }
}


memoize ('_find_cv_by_name');
sub _find_cv_by_name {
  my $cv_name = shift;

  return $chado->resultset('Cv::Cv')->find({ name => $cv_name })
    or die "no cv with name: $cv_name\n";
}


my %new_cc_ids = ();

sub _get_cc_id {
  my $cv_name = shift;

  if (!exists $new_cc_ids{$cv_name}) {
    $new_cc_ids{$cv_name} = 0;
  }

  return $new_cc_ids{$cv_name}++;
}


memoize ('_find_or_create_pub');
sub _find_or_create_pub {
  my $pubmed_identifier = shift;

  my $pub_rs = $chado->resultset('Pub::Pub');

  return $pub_rs->find_or_create({ uniquename => $pubmed_identifier,
                                   type_id => $unfetched_pub_cvterm->cvterm_id() });
}


memoize ('_find_cvterm');
sub _find_cvterm {
  my $cv_name = shift;
  my $term_name = shift;

  my $cv = _find_cv_by_name($cv_name);

  return $chado->resultset('Cv::Cvterm')->find({ name => $cv_name, cv => $cv });
}


memoize ('_find_or_create_cvterm');
sub _find_or_create_cvterm {
  my $cv_name = shift;
  my $term_name = shift;

  my $cv = _find_cv_by_name($cv_name);

  my $cvterm = _find_cvterm($cv_name, $term_name);

  if (!defined $cvterm) {
    my $new_ont_id = _get_cc_id($cv_name);
    my $formatted_id = sprintf "%07d", $new_ont_id;

    my $dbxref_rs = $chado->resultset('General::Dbxref');
    my $dbxref = $dbxref_rs->create({ db_id => $pombase_dbs{phenotype}->db_id(),
                                      accession => $formatted_id });

    my $cvterm_rs = $chado->resultset('Cv::Cvterm');
    $cvterm = $cvterm_rs->create({ name => $term_name,
                                   dbxref_id => $dbxref->dbxref_id(),
                                   cv_id => $cv->cv_id() });
  }

  return $cvterm;
}

memoize ('_find_chado_feature');
sub _find_chado_feature {
  my $systematic_id = shift;

  my $rs = $chado->resultset('Sequence::Feature');
  return $rs->find({ uniquename => $systematic_id })
    or die "can't find feature for: $systematic_id\n";
}


sub _add_feature_cvterm {
  my $systematic_id = shift;
  my $cvterm = shift;
  my $pub = shift;

  my $chado_feature = _find_chado_feature($systematic_id);

  my $rs = $chado->resultset('Sequence::FeatureCvterm');

  $rs->create({ feature_id => $chado_feature->feature_id(),
                cvterm_id => $cvterm->cvterm_id(),
                pub_id => $pub->pub_id() });
}

sub _process_one_cc {
  my $systematic_id = shift;
  my $bioperl_feature = shift;
  my $cc_qualifier = shift;

  print "  cc:\n" if $verbose;

  my @bits = split /;/, $cc_qualifier;

  my %cc_map = ();

  for my $bit (@bits) {
    if ($bit =~ /\s*([^=]+?)\s*=\s*([^=]+?)\s*$/) {
      my $name = $1;
      my $value = $2;

      print "    $name => $value\n" if $verbose;

      if (exists $cc_map{$name}) {
        warn "duplicated sub-qualifier '$name' in $systematic_id from:
/controlled_curation=\"$cc_qualifier\"\n";
      }

      $cc_map{$name} = $value;
    }
  }

  if (defined $cc_map{cv}) {
    if ($cc_map{cv} eq 'phenotype') {
      $cc_map{term} =~ s/$cc_map{cv}, //;

      my $cvterm = _find_or_create_cvterm($cc_map{cv}, $cc_map{term});

      if (defined $cc_map{db_xref} && $cc_map{db_xref} =~ /^(PMID:(.*))/) {
        my $pub = _find_or_create_pub($1);

        _add_feature_cvterm($systematic_id, $cvterm, $pub);

        warn "loaded: $cc_qualifier\n";

        return;
      } else {
        warn "no db_xref in $cc_qualifier from:\n";
        _dump_feature($bioperl_feature);
        exit(1);
      }
    }

    warn "didn't process: $cc_qualifier\n";

  } else {
    warn "no cv name for: $cc_qualifier\n";
  }
}


while (defined (my $file = shift)) {

  my $io = Bio::SeqIO->new(-file => $file, -format => "embl" );
  my $seq_obj = $io->next_seq;
  my $anno_collection = $seq_obj->annotation;

  my $phenotype_process = sub {
    my $systematic_id = shift;
    my %qualifiers = @_;


  };

  my %cv_processes = (
    phenotype => $phenotype_process,
  );

  for my $bioperl_feature ($seq_obj->get_SeqFeatures) {
    my $type = $bioperl_feature->primary_tag();

    next unless $type eq 'CDS';

    my @systematic_ids = $bioperl_feature->get_tag_values("systematic_id");

    if (@systematic_ids != 1) {
      my $systematic_id_count = scalar(@systematic_ids);
      warn "\nexpected 1 systematic_id, got $systematic_id_count, for:";
      _dump_feature($bioperl_feature);
      exit(1);
    }

    my $systematic_id = $systematic_ids[0];

    print "$type: $systematic_id\n" if $verbose;
    if ($bioperl_feature->has_tag("controlled_curation")) {
      for my $value ($bioperl_feature->get_tag_values("controlled_curation")) {
        _process_one_cc($systematic_id, $bioperl_feature, $value);
      }
    }
  }

  #exit (1);

}

#$guard->commit;
