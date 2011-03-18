#!/usr/bin/perl -w

use perl5i::2;

use Bio::SeqIO;
use Bio::Chado::Schema;
use Memoize;
use Getopt::Std;

BEGIN {
  push @INC, 'lib';
};

use PomBase::Chado;
use PomBase::Load;

my $verbose = 0;
my $quiet = 0;
my $dry_run = 0;
my $test = 0;

sub usage {
  die "$0 [-v] [-d] <embl_file> ...\n";
}

my %opts = ();

if (!getopts('vdqt', \%opts)) {
  usage();
}

if ($opts{v}) {
  $verbose = 1;
}
if ($opts{q}) {
  $quiet = 1;
}
if ($opts{d}) {
  $dry_run = 1;
}
if ($opts{t}) {
  $test = 1;
}

my $database = shift;

my $chado = PomBase::Chado::connect($database, 'kmr44', 'kmr44');

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

my %cv_alt_names = (
  genome_org => ['genome organisation', 'genome organization'],
  sequence_feature => ['sequence feature'],
  species_dist => ['species distribution'],
  localization => ['localisation'],
  phenotype => [],
  pt_mod => ['modification'],
  gene_ex => ['expression'],
  m_f_g => ['misc functional group'],
  name_derivation => ['name description'],
  pathway => [],
  complementation => [],
  protein_family => [],
  ex_tools => [],
  misc => [],
  warning => [],
  DNA_binding_specificity => [],
  subunit_composition => [],
  cat_act => ['catalytic activity'],
  disease_associated => ['disease associated'],
);

my %cv_long_names = (
  'genome organisation' => 'genome_org',
  'genome organization' => 'genome_org',
  'sequence feature' => 'sequence_feature',
  'species distribution' => 'species_dist',
  'localisation' => 'localization',
  'localization' => 'localization',
  'modification' => 'pt_mod',
  'expression' => 'gene_ex',
  'misc functional group' => 'm_f_g',
  'name description' => 'name_derivation',
  'catalytic activity' => 'cat_act',
  'phenotype' => 'phenotype',
  'disease associated' => 'disease_associated',
);

my $guard = $chado->txn_scope_guard;

my $cv_rs = $chado->resultset('Cv::Cv');

my $genedb_literature_cv = $cv_rs->find({ name => 'genedb_literature' });
my $feature_cvtermprop_type_cv =
  $cv_rs->create({ name => 'feature_cvtermprop_type' });
my $feature_relationshipprop_type_cv =
  $cv_rs->create({ name => 'feature_relationshipprop_type' });

my $cvterm_rs = $chado->resultset('Cv::Cvterm');

my $unfetched_pub_cvterm =
  $cvterm_rs->find({ name => 'unfetched',
                     cv_id => $genedb_literature_cv->cv_id() });

my %pombase_dbs = ();

my $db_rs = $chado->resultset('General::Db');

$db_rs->create({ name => 'KOG',
                 description => 'EuKaryotic Orthologous Groups' });

$pombase_dbs{phenotype} = $db_rs->create({ name => 'PomBase phenotype' });
my $pombase_db = $db_rs->create({ name => 'PomBase' });

$pombase_dbs{feature_cvtermprop_type} = $pombase_db;
$pombase_dbs{feature_relationshipprop_type} = $pombase_db;
$pombase_dbs{$go_cv_map{P}} = $pombase_db;
$pombase_dbs{$go_cv_map{F}} = $pombase_db;
$pombase_dbs{$go_cv_map{C}} = $pombase_db;

for my $extra_cv_name (keys %cv_alt_names) {
  $cv_rs->create({ name => $extra_cv_name });

  if (!defined $pombase_dbs{$extra_cv_name}) {
    $pombase_dbs{$extra_cv_name} = $pombase_db;
  }
}

my $null_pub = $chado->resultset('Pub::Pub')->find({ uniquename => 'null' });

my $orthologous_to_cvterm =
  $chado->resultset('Cv::Cvterm')->find({ name => 'orthologous_to' });

warn "loading genes ...\n" unless $quiet;
my $new_objects;

if (!$test) {
  $new_objects = PomBase::Load::init_objects($chado);
}

sub _dump_feature {
  my $feature = shift;

  for my $tag ($feature->get_all_tags) {
    warn "    tag: ", $tag, "\n";
    for my $value ($feature->get_tag_values($tag)) {
      warn "      value: ", $value, "\n";
    }
  }
}


func _find_cv_by_name($cv_name) {
  die 'no $cv_name' unless defined $cv_name;

  return ($chado->resultset('Cv::Cv')->find({ name => $cv_name })
    or die "no cv with name: $cv_name\n");
}
memoize ('_find_cv_by_name');


my %new_cvterm_ids = ();

# return an ID for a new term in the CV with the given name
func _get_cvterm_id($db_name) {
  if (!exists $new_cvterm_ids{$db_name}) {
    $new_cvterm_ids{$db_name} = 1_000_000;
  }

  return $new_cvterm_ids{$db_name}++;
}


func _find_or_create_pub($pubmed_identifier) {
  my $pub_rs = $chado->resultset('Pub::Pub');

  return $pub_rs->find_or_create({ uniquename => $pubmed_identifier,
                                   type_id => $unfetched_pub_cvterm->cvterm_id() });
}
memoize ('_find_or_create_pub');


func _find_cvterm($cv, $term_name) {
  warn "  _find_cvterm(", $cv->name(), ", $term_name)\n" if $verbose;

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
#memoize ('_find_cvterm');


func _find_or_create_cvterm($cv, $term_name) {
  my $cvterm = _find_cvterm($cv, $term_name);

  # nested transaction
  my $cvterm_guard = $chado->txn_scope_guard();

  if (defined $cvterm) {
    warn "  found cvterm_id ", $cvterm->cvterm_id(),
      " when looking for $term_name in ", $cv->name(),"\n" if $verbose;
  } else {
    warn "  failed to find: $term_name in ", $cv->name(), "\n" if $verbose;

    my $db_name = $pombase_dbs{$cv->name()};
    if (!defined $db_name) {
      die "no db name for ", $cv->name(), "\n";
    }

    my $new_ont_id = _get_cvterm_id($db_name);
    my $formatted_id = sprintf "%07d", $new_ont_id;

    my $dbxref_rs = $chado->resultset('General::Dbxref');
    my $db = $pombase_dbs{$cv->name()};

    die "no db for ", $cv->name(), "\n" if !defined $db;

    warn "  creating dbxref $formatted_id, ", $cv->name(), "\n" if $verbose;

    my $dbxref =
      $dbxref_rs->create({ db_id => $db->db_id(),
                           accession => $formatted_id });

    my $cvterm_rs = $chado->resultset('Cv::Cvterm');
    $cvterm = $cvterm_rs->create({ name => $term_name,
                                   dbxref_id => $dbxref->dbxref_id(),
                                   cv_id => $cv->cv_id() });

    warn "  created new cvterm, id: ", $cvterm->cvterm_id(), "\n" if $verbose;
  }

  $cvterm_guard->commit();

  return $cvterm;
}
memoize ('_find_or_create_cvterm');


func _find_chado_feature ($systematic_id, $try_name) {
  my $rs = $chado->resultset('Sequence::Feature');
  my $feature = $rs->find({ uniquename => $systematic_id });

  return $feature if defined $feature;

  if ($try_name) {
    $feature = $rs->find({ name => $systematic_id });

    return $feature if defined $feature;
  }

  die "can't find feature for: $systematic_id\n";
}
memoize ('_find_chado_feature');


my %stored_cvterms = ();

func _create_feature_cvterm($pombe_gene, $cvterm, $pub) {
  my $rs = $chado->resultset('Sequence::FeatureCvterm');

  my $systematic_id = $pombe_gene->uniquename();

  if (!exists $stored_cvterms{$cvterm->name()}{$systematic_id}{$pub->uniquename()}) {
    $stored_cvterms{$cvterm->name()}{$systematic_id}{$pub->uniquename()} = 0;
  }

  my $rank =
    $stored_cvterms{$cvterm->name()}{$systematic_id}{$pub->uniquename()}++;

  return $rs->create({ feature_id => $pombe_gene->feature_id(),
                       cvterm_id => $cvterm->cvterm_id(),
                       pub_id => $pub->pub_id(),
                       rank => $rank });
}

func _add_feature_cvtermprop($feature_cvterm, $name, $value) {
  if (!defined $name) {
    die "no name for property\n";
  }
  if (!defined $value) {
    die "no value for $name\n";
  }

  my $type = _find_or_create_cvterm($feature_cvtermprop_type_cv,
                                    $name);

  my $rs = $chado->resultset('Sequence::FeatureCvtermprop');

  warn "    adding feature_cvtermprop $name => $value\n" if $verbose;

  return $rs->create({ feature_cvterm_id =>
                         $feature_cvterm->feature_cvterm_id(),
                       type_id => $type->cvterm_id(),
                       value => $value,
                       rank => 0 });
}

func _add_feature_relationshipprop($feature_relationship, $name, $value) {
  if (!defined $name) {
    die "no name for property\n";
  }
  if (!defined $value) {
    die "no value for $name\n";
  }

  my $type = _find_or_create_cvterm($feature_relationshipprop_type_cv,
                                    $name);

  my $rs = $chado->resultset('Sequence::FeatureRelationshipprop');

  warn "    adding feature_relationshipprop $name => $value\n" if $verbose;

  return $rs->create({ feature_relationship_id =>
                         $feature_relationship->feature_relationship_id(),
                       type_id => $type->cvterm_id(),
                       value => $value,
                       rank => 0 });
}

func _is_go_cv_name($cv_name) {
  return grep { $_ eq $cv_name } values %go_cv_map;
}

func _get_and_check_date($sub_qual_map) {
  my $date = delete $sub_qual_map->{date};

  if (defined $date) {
    if ($date =~ /(\d\d\d\d)(\d\d)(\d\d)/) {
      if ($1 > 2011) {
        warn "date is in the future: $date\n";
      } else {
        if ($2 < 1 || $2 > 12) {
          warn "month ($2) not in range 1..12\n";
        }
        if ($3 < 1 || $3 > 31) {
          warn "day ($3) not in range 1..31\n";
        }
      }
      return $date;
    } else {
      warn "  unknown date format: $date\n";
    }
  }

  return undef;
}

func _get_pub_from_dbxref($term, $sub_qual_map) {
  my $db_xref = delete $sub_qual_map->{db_xref};

  if (defined $db_xref) {
    if ($db_xref =~ /^(PMID:(.*))/) {
      return _find_or_create_pub($1);
    } else {
      warn "  qualifier for $term ",
        " has unknown format db_xref (", $db_xref,
          ") - using null publication\n" unless $quiet;
      return $null_pub;
    }
  } else {
    warn "  qualifier for $term ",
      " has no db_xref - using null publication\n" unless $quiet;
    return $null_pub;
  }

}

func _add_term_to_gene($pombe_gene, $cv_name, $term, $sub_qual_map) {
  my $cv = _find_cv_by_name($cv_name);

  my $db_accession;

  if (_is_go_cv_name($cv_name)) {
    $db_accession = $sub_qual_map->{GOid};

    if (!defined $db_accession) {
      my $systematic_id = $pombe_gene->uniquename();

      warn "  no GOid for $systematic_id annotation $term\n";
    }
  }

  my $cvterm = _find_or_create_cvterm($cv, $term, $db_accession);
  my $pub = _get_pub_from_dbxref($term, $sub_qual_map);

  my $featurecvterm = _create_feature_cvterm($pombe_gene, $cvterm, $pub);

  if (_is_go_cv_name($cv_name)) {
    my $evidence_code = delete $sub_qual_map->{evidence};

    my $evidence;

    if (defined $evidence_code) {
      $evidence = $go_evidence_codes{$evidence_code};
    } else {
      warn "no evidence for: $term in ", $pombe_gene->uniquename(), "\n";
      $evidence = "NO EVIDENCE";
    }

    if (defined $sub_qual_map->{with}) {
      $evidence .= " with " . delete $sub_qual_map->{with};
    }
    if (defined $sub_qual_map->{from}) {
      $evidence .= " from " . delete $sub_qual_map->{from};
    }
    _add_feature_cvtermprop($featurecvterm,
                            evidence => $evidence);

    if (defined $sub_qual_map->{residue}) {
      _add_feature_cvtermprop($featurecvterm,
                              residue => delete $sub_qual_map->{residue});
    }
  }

  my $qualifier = delete $sub_qual_map->{qualifier};
  if (defined $qualifier) {
    _add_feature_cvtermprop($featurecvterm, qualifier => $qualifier);
  }

  my $date = _get_and_check_date($sub_qual_map);
  if (defined $date) {
    _add_feature_cvtermprop($featurecvterm, date => $date);
  }
}

func _split_sub_qualifiers($cc_qualifier) {
  my %map = ();

  my @bits = split /;/, $cc_qualifier;

  for my $bit (@bits) {
    if ($bit =~ /\s*([^=]+?)\s*=\s*(.*?)\s*$/) {
      my $name = $1;
      my $value = $2;
      if (exists $map{$name}) {
        die "duplicated sub-qualifier '$name' from:
/controlled_curation=\"$cc_qualifier\"\n";
      }

      $map{$name} = $value;

      if ($name =~ / /) {
        warn "  qualifier name ('$name') contains a space\n" unless $quiet;
      }

      if ($name eq 'cv' && $value =~ / /) {
        warn "  cv name ('$value') contains a space\n" unless $quiet;
      }
    }
  }

  return %map;
}

func _add_feature_relationship_pub($relationship, $pub) {
  my $rs = $chado->resultset('Sequence::FeatureRelationshipPub');

  warn "    adding pub ", $pub->pub_id(), " to feature_relationship ",
    $relationship->feature_relationship_id() , "\n" if $verbose;

  return $rs->create({ feature_relationship_id =>
                         $relationship->feature_relationship_id(),
                       pub_id => $pub->pub_id() });

}

func _process_ortholog($pombe_gene, $term, $sub_qual_map) {
  my $org_name;
  my $gene_bit;

  my $date = delete $sub_qual_map->{date};

  if ($term =~ /^orthologous to S\. cerevisiae (.*)/) {
    $gene_bit = $1;
  } else {
    if ($term =~ /^human\s+(.*?)\s+ortholog$/) {
      $gene_bit = $1;
    } else {
      warn "  not recognised as an ortholog curation: $term\n" if $verbose;
      return 0;
    }
  }

  my @gene_names = ();

  if ($gene_bit =~ /^\S+$/) {
    push @gene_names, $gene_bit;
  } else {
    if ($gene_bit =~ /^(\S+) and (\S+)/) {
      push @gene_names, $1, $2;
    } else {
      warn qq(can't parse: "$gene_bit" from "$term"\n);
      return 0;
    }
  }

  for my $ortholog_name (@gene_names) {
    warn "  creating ortholog from ", $pombe_gene->uniquename(),
      " to $ortholog_name\n" if $verbose;

    my $ortholog_feature = undef;
    try {
      $ortholog_feature = _find_chado_feature($ortholog_name, 1);
    };

    if (!defined $ortholog_feature) {
      warn "  ortholog ($ortholog_name) not found\n";
      return 0;
    }

    my $rel_rs = $chado->resultset('Sequence::FeatureRelationship');

    try {
      my $orth_guard = $chado->txn_scope_guard;
      my $rel = $rel_rs->create({ object_id => $pombe_gene->feature_id(),
                                  subject_id => $ortholog_feature->feature_id(),
                                  type_id => $orthologous_to_cvterm->cvterm_id()
                                });
      _add_feature_relationshipprop($rel, 'date', $date);
      my $pub = _get_pub_from_dbxref($term, $sub_qual_map);
      _add_feature_relationship_pub($rel, $pub);
      $orth_guard->commit();
    } catch {
      warn "failed to create ortholog relation: $_\n";
      return 0;
    };
  }

  return 1;
}


func _process_one_cc($pombe_gene, $bioperl_feature, $qualifier) {
  my $systematic_id = $pombe_gene->uniquename();

  warn "  _process_one_cc($systematic_id, $bioperl_feature, '$qualifier')\n"
    if $verbose;

  my %qual_map = ();

  try {
    %qual_map = _split_sub_qualifiers($qualifier);
  } catch {
    warn "  $_: failed to process sub-qualifiers from $qualifier, feature:\n";
    _dump_feature($bioperl_feature);
  };

  if ((scalar(keys %qual_map)) == 0) {
    return ();
  }

  my $cv_name = delete $qual_map{cv};
  my $term = delete $qual_map{term};

  if (!defined $term || length $term == 0) {
    warn "no term for: $qualifier\n";
    return ();
  }

  if (!defined $cv_name) {
    map {
      my $long_name = $_;

      if ($term =~ s/$long_name, *//) {
        my $short_cv_name = $cv_long_names{$long_name};
        $cv_name = $short_cv_name;
      }
    } keys %cv_long_names;
  }

  if (defined $cv_name) {
    $term =~ s/$cv_name, *//;

    if (exists $cv_alt_names{$cv_name}) {
      map { $term =~ s/$_, *//; } @{$cv_alt_names{$cv_name}};
    }

    if (grep { $_ eq $cv_name } keys %cv_alt_names) {
      try {
        _add_term_to_gene($pombe_gene, $cv_name, $term, \%qual_map);
      } catch {
        warn "  $_: failed to load qualifier '$qualifier' from $systematic_id\n";
        _dump_feature($bioperl_feature) if $verbose;
        return ();
      };
      warn "  loaded: $qualifier\n" unless $quiet;
      return ();
    }

    warn "  unknown cv $cv_name: $qualifier\n";
  } else {
    if (!_process_ortholog($pombe_gene, $term, \%qual_map)) {
      warn "  didn't process: $qualifier\n";
      return ();
    }
  }

  return %qual_map;
}

func _process_one_go_qual($pombe_gene, $bioperl_feature, $qualifier) {
  warn "    go qualifier: $qualifier\n" if $verbose;

  my %qual_map = ();

  try {
    %qual_map = _split_sub_qualifiers($qualifier);
  } catch {
    warn "  $_: failed to process sub-qualifiers from $qualifier, feature:\n";
    _dump_feature($bioperl_feature);
  };

  if ((scalar(keys %qual_map)) == 0) {
    return ();
  }

  my $aspect = delete $qual_map{aspect};

  if (defined $aspect) {
    my $cv_name = $go_cv_map{uc $aspect};

    my $term = delete $qual_map{term};

    try {
      _add_term_to_gene($pombe_gene, $cv_name, $term, \%qual_map);
    } catch {
      my $systematic_id = $pombe_gene->uniquename();
      warn "  $_: failed to load qualifier '$qualifier' from $systematic_id:\n";
      _dump_feature($bioperl_feature) if $verbose;
      return ();
    };
    warn "  loaded: $qualifier\n" if $verbose;
  } else {
    warn "  no aspect for: $qualifier\n";
    return ();
  }

  return %qual_map;
}

sub _check_unused_quals
{
  return if $quiet;

  my $qual_text = shift;
  my %quals = @_;

  if (scalar(keys %quals) > 0) {
    warn "  unprocessed sub qualifiers:\n";
    while (my ($key, $value) = each %quals) {
      warn "     $key => $value\n";
    }
  }
}

# main loop:
#process all features from the input files
while (defined (my $file = shift)) {

  my $io = Bio::SeqIO->new(-file => $file, -format => "embl" );
  my $seq_obj = $io->next_seq;
  my $anno_collection = $seq_obj->annotation;

  for my $bioperl_feature ($seq_obj->get_SeqFeatures) {
    my $type = $bioperl_feature->primary_tag();

    next unless $bioperl_feature->has_tag("systematic_id");

    my @systematic_ids = $bioperl_feature->get_tag_values("systematic_id");

    if (@systematic_ids != 1) {
      my $systematic_id_count = scalar(@systematic_ids);
      warn "\n  expected 1 systematic_id, got $systematic_id_count, for:";
      _dump_feature($bioperl_feature);
      exit(1);
    }

    my $systematic_id = $systematic_ids[0];

    warn "processing $type $systematic_id\n";

    my $pombe_gene = undef;

    try {
      $pombe_gene = _find_chado_feature($systematic_id);
    } catch {
      warn "no feature found for $type $systematic_id\n";
    };

    next if not defined $pombe_gene;

    if ($bioperl_feature->has_tag("controlled_curation")) {
      for my $value ($bioperl_feature->get_tag_values("controlled_curation")) {
        my %unused_quals = _process_one_cc($pombe_gene, $bioperl_feature, $value);
        _check_unused_quals($value, %unused_quals);
        warn "\n" if $verbose;
      }
    }

    if ($bioperl_feature->has_tag("GO")) {
      for my $value ($bioperl_feature->get_tag_values("GO")) {
        my %unused_quals = _process_one_go_qual($pombe_gene, $bioperl_feature, $value);
        warn "\n" if $verbose;

        _check_unused_quals($value, %unused_quals);
      }
    }
  }
}

$guard->commit unless $dry_run;
