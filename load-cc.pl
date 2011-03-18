#!/usr/bin/perl -w

use strict;
use warnings;
use Carp;

use Bio::SeqIO;
use Bio::Chado::Schema;
use Memoize;
use Try::Tiny;
use Method::Signatures;
use Getopt::Std;

my $verbose = 0;
my $dry_run = 0;

sub usage {
  die "$0 [-v] [-d] <embl_file> ...\n";
}

my %opts = ();

if (!getopts('vd', \%opts)) {
  usage();
}

if ($opts{v}) {
  $verbose = 1;
}
if ($opts{d}) {
  $dry_run = 1;
}

my %go_evidence_codes = (
  EXP => 'Inferred from Experiment',
  IDA => 'Inferred from Direct Assay',
  IPI => 'Inferred from Physical Interaction',
  IMP => 'Inferred from Mutant Phenotype',
  IGI => 'Inferred from Genetic Interaction',
  IEP => 'Inferred from Expression Pattern',
  ISS => 'Inferred from Sequence or Structural Similarity',
  ISO => 'Inferred from Sequence Orthology',
  ISA => 'Inferred from Sequence Alignment',
  ISM => 'Inferred from Sequence Model',
  IGC => 'Inferred from Genomic Context',
  RCA => 'inferred from Reviewed Computational Analysis',
  TAS => 'Traceable Author Statement',
  NAS => 'Non-traceable Author Statement',
  IC => 'Inferred by Curator',
  ND => 'No biological Data available',
  IEA => 'Inferred from Electronic Annotation',
  NR => 'Not Recorded',
);

my %go_cv_map = (
  P => 'biological_process',
  F => 'molecular_function',
  C => 'cellular_component',
);

my $chado = Bio::Chado::Schema->connect('dbi:Pg:database=pombe-kmr-qual-dev-4',
                                        'kmr44', 'kmr44');

my $guard = $chado->txn_scope_guard;

my $cv_rs = $chado->resultset('Cv::Cv');

my $genedb_literature_cv = $cv_rs->find({ name => 'genedb_literature' });
my $phenotype_cv = $cv_rs->create({ name => 'phenotype' });
my $feature_cvtermprop_type_cv =
  $cv_rs->create({ name => 'feature_cvtermprop_type' });

my $cvterm_rs = $chado->resultset('Cv::Cvterm');

my $unfetched_pub_cvterm =
  $cvterm_rs->find({ name => 'unfetched',
                     cv_id => $genedb_literature_cv->cv_id() });

my %pombase_dbs = ();

$pombase_dbs{phenotype} =
  $chado->resultset('General::Db')->create({ name => 'PomBase phenotype' });

my $pombase_db =
  $chado->resultset('General::Db')->create({ name => 'PomBase' });

$pombase_dbs{feature_cvtermprop_type} = $pombase_db;

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
func _find_cv_by_name($cv_name) {
  die 'no $cv_name' unless defined $cv_name;

  return ($chado->resultset('Cv::Cv')->find({ name => $cv_name })
    or die "no cv with name: $cv_name\n");
}


my %new_cc_ids = ();

# return an ID for a new term in the CV with the given name
func _get_cc_id($cv_name) {
  if (!exists $new_cc_ids{$cv_name}) {
    $new_cc_ids{$cv_name} = 0;
  }

  return $new_cc_ids{$cv_name}++;
}


memoize ('_find_or_create_pub');
func _find_or_create_pub($pubmed_identifier) {
  my $pub_rs = $chado->resultset('Pub::Pub');

  return $pub_rs->find_or_create({ uniquename => $pubmed_identifier,
                                   type_id => $unfetched_pub_cvterm->cvterm_id() });
}


memoize ('_find_cvterm');
func _find_cvterm($cv, $term_name) {
  warn "_find_cvterm(", $cv->name(), ", $term_name)\n";

  my $cvterm_rs = $chado->resultset('Cv::Cvterm');
  my $cvterm = $cvterm_rs->find({ name => $term_name, cv_id => $cv->cv_id() });

  if (defined $cvterm) {
    return $cvterm;
  } else {
    my $synonym_type_cv = _find_cv_by_name('synonym_type');
    my $exact = _find_cvterm($synonym_type_cv, 'exact');

    my $synonym_rs = $chado->resultset('Cv::Cvtermsynonym');
    my $search_rs = $synonym_rs->search({ synonym => $term_name,
                                          type_id => $exact->cvterm_id() });

    if ($search_rs->count() > 1) {
      die "more than one cvtermsynonym found for $term_name\n";
    } else {
      my $synonym = $search_rs->next();

      if (defined $synonym) {
        return $cvterm_rs->find($synonym->cvterm_id());
      } else {
        return undef;
      }
    }
  }
}


memoize ('_find_or_create_cvterm');
func _find_or_create_cvterm($cv, $term_name) {
  my $cvterm = _find_cvterm($cv, $term_name);

  if (defined $cvterm) {
    warn "found ", $cvterm->cvterm_id(), " for $term_name in ",
      $cv->name(),"\n";
  } else {
    warn "failed to find: $term_name in ", $cv->name(), "\n" if $verbose;

    my $new_ont_id = _get_cc_id($cv->name());
    my $formatted_id = sprintf "%07d", $new_ont_id;

    my $dbxref_rs = $chado->resultset('General::Dbxref');
    my $db = $pombase_dbs{$cv->name()};

    die "no db for ", $cv->name(), "\n" if !defined $db;

    my $dbxref =
      $dbxref_rs->create({ db_id => $db->db_id(),
                           accession => $formatted_id });

    my $cvterm_rs = $chado->resultset('Cv::Cvterm');
    $cvterm = $cvterm_rs->create({ name => $term_name,
                                   dbxref_id => $dbxref->dbxref_id(),
                                   cv_id => $cv->cv_id() });
  }

  return $cvterm;
}

memoize ('_find_chado_feature');
func _find_chado_feature ($systematic_id) {

  my $rs = $chado->resultset('Sequence::Feature');
  return $rs->find({ uniquename => $systematic_id })
    or die "can't find feature for: $systematic_id\n";
}


func _add_feature_cvterm($systematic_id, $cvterm, $pub) {
  my $chado_feature = _find_chado_feature($systematic_id);
  my $rs = $chado->resultset('Sequence::FeatureCvterm');

  return $rs->create({ feature_id => $chado_feature->feature_id(),
                       cvterm_id => $cvterm->cvterm_id(),
                       pub_id => $pub->pub_id() });
}

func _add_feature_cvtermprop($feature_cvterm, $name, $value) {
  if (!defined $name) {
    die "no name for $feature_cvterm\n";
  }
  if (!defined $value) {
    die "no value for $name\n";
  }

  my $type = _find_or_create_cvterm($feature_cvtermprop_type_cv,
                                    $name);

  my $rs = $chado->resultset('Sequence::FeatureCvtermprop');

  return $rs->create({ feature_cvterm_id =>
                         $feature_cvterm->feature_cvterm_id(),
                       type_id => $type->cvterm_id(),
                       value => $value,
                       rank => 0 });
}

func _is_go_cv_name($cv_name) {
  return grep { $_ eq $cv_name } values %go_cv_map;
}

sub _add_cvterm {
  my $systematic_id = shift;
  my $cv_name = shift;
  my $cc_map = shift;

  my $cv = _find_cv_by_name($cv_name);

  my $term = $cc_map->{term};

  my $db_accession;

  if (_is_go_cv_name($cv_name)) {
    $db_accession = $cc_map->{GOid};

    if (!defined $db_accession) {
      warn "no GOid for $systematic_id annotation $term\n";
    }
  }

  my $cvterm = _find_or_create_cvterm($cv, $term, $db_accession);

  if (defined $cc_map->{db_xref} && $cc_map->{db_xref} =~ /^(PMID:(.*))/) {
    my $pub = _find_or_create_pub($1);

    my $featurecvterm = _add_feature_cvterm($systematic_id, $cvterm, $pub);

    warn "\n============== $cv_name\n";

    if (_is_go_cv_name($cv_name)) {
      my $evidence = $go_evidence_codes{$cc_map->{evidence}};
      _add_feature_cvtermprop($featurecvterm, evidence => $evidence);
      _add_feature_cvtermprop($featurecvterm, date => $cc_map->{date});
    } else {
      _add_feature_cvtermprop($featurecvterm,
                              qualifier => $cc_map->{qualifier});
    }
  } else {
    die "qualifier has no db_xref\n";
  }
}

func _split_sub_qualifiers($cc_qualifier) {
  my %map = ();

  my @bits = split /;/, $cc_qualifier;

  for my $bit (@bits) {
    if ($bit =~ /\s*([^=]+?)\s*=\s*([^=]+?)\s*$/) {
      my $name = $1;
      my $value = $2;

      print "    $name => $value\n" if $verbose;

      if (exists $map{$name}) {
        die "duplicated sub-qualifier '$name' from:
/controlled_curation=\"$cc_qualifier\"\n";
      }

      $map{$name} = $value;
    }
  }

  return %map;
}

func _process_one_cc($systematic_id, $bioperl_feature, $cc_qualifier) {
  print "  cc: $cc_qualifier\n" if $verbose;

  my %cc_map;

  try {
    %cc_map = _split_sub_qualifiers($cc_qualifier);
  } catch {
    warn "$_: failed to process sub-qualifiers from $cc_qualifier, feature:\n";
    _dump_feature($bioperl_feature);
    return;
  };

  $cc_map{term} =~ s/$cc_map{cv}, //;

  if (defined $cc_map{cv}) {
    if ($cc_map{cv} eq 'phenotype') {
      try {
        _add_cvterm($systematic_id, $cc_map{cv}, \%cc_map);
      } catch {
        warn "$_: failed to load qualifier from $cc_qualifier, feature:\n";
        _dump_feature($bioperl_feature);
        exit(1);
      };
      warn "loaded: $cc_qualifier\n";
      return;
    }

    warn "didn't process: $cc_qualifier\n";
  } else {
    warn "no cv name for: $cc_qualifier\n";
  }
}

func _process_one_go_qual($systematic_id, $bioperl_feature, $go_qualifier) {
  print "  go qualifier: $go_qualifier\n" if $verbose;

  my %qual_map;

  try {
    %qual_map = _split_sub_qualifiers($go_qualifier);
  } catch {
    warn "$_: failed to process sub-qualifiers from $go_qualifier, feature:\n";
    _dump_feature($bioperl_feature);
    return;
  };

  my $aspect = $qual_map{aspect};

  if (defined $aspect) {
    my $cv_name = $go_cv_map{$aspect};

    try {
      _add_cvterm($systematic_id, $cv_name, \%qual_map);
    } catch {
      warn "$_: failed to load qualifier from $go_qualifier, feature:\n";
      _dump_feature($bioperl_feature);
      exit(1);
    };
    warn "loaded: $go_qualifier\n" if $verbose;
  } else {
    warn "no aspect for: $go_qualifier\n";
  }

}


# main loop:
#  process all features from the input files
while (defined (my $file = shift)) {

  my $io = Bio::SeqIO->new(-file => $file, -format => "embl" );
  my $seq_obj = $io->next_seq;
  my $anno_collection = $seq_obj->annotation;

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

    if ($bioperl_feature->has_tag("GO")) {
      for my $value ($bioperl_feature->get_tag_values("GO")) {
        _process_one_go_qual($systematic_id, $bioperl_feature, $value);
      }
    }
  }
}

$guard->commit unless $dry_run;
