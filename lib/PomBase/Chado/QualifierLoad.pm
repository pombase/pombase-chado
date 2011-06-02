package PomBase::Chado::QualifierLoad;

=head1 NAME

PomBase::Chado::QualifierLoad - Load a Chado database from Sanger PGG EMBL files

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::QualifierLoad

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Carp;

use Moose;

use Memoize;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::FeatureDumper';

has verbose => (is => 'ro', isa => 'Bool');
has objs => (is => 'ro', isa => 'HashRef[Str]', default => sub { {} });

my %go_cv_map = (
  P => 'biological_process',
  F => 'molecular_function',
  C => 'cellular_component',
);

method get_go_cv_map
{
  return \%go_cv_map;
}

method BUILD
{
  my $chado = $self->chado();

  $self->objs()->{go_evidence_codes} = {
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
  };

  $self->objs()->{cv_alt_names} = {
    genome_org => ['genome organisation', 'genome organization'],
    sequence_feature => ['sequence feature'],
    species_dist => ['species distribution'],
    localization => ['localisation'],
    phenotype => [],
    pt_mod => ['modification'],
    gene_ex => ['expression'],
    m_f_g => ['misc functional group'],
    name_description => ['name description'],
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
  };

  $self->objs()->{cv_long_names} = {
    'genome organisation' => 'genome_org',
    'genome organization' => 'genome_org',
    'sequence feature' => 'sequence_feature',
    'species distribution' => 'species_dist',
    'localisation' => 'localization',
    'localization' => 'localization',
    'modification' => 'pt_mod',
    'expression' => 'gene_ex',
    'misc functional group' => 'm_f_g',
    'name description' => 'name_description',
    'catalytic activity' => 'cat_act',
    'phenotype' => 'phenotype',
    'disease associated' => 'disease_associated',
  };

  for my $cv_name (keys %{$self->objs()->{cv_alt_names}}) {
    if (!exists $self->objs()->{cv_long_names}->{$cv_name}) {
      $self->objs()->{cv_long_names}->{$cv_name} = $cv_name;
    }
  }


  my $db_rs = $chado->resultset('General::Db');

  $db_rs->find_or_create({ name => 'KOG',
                           description => 'EuKaryotic Orthologous Groups' });

  my %pombase_dbs = ();

  $pombase_dbs{phenotype} = $db_rs->find_or_create({ name => 'SPO' });
  my $pombase_db = $db_rs->find_or_create({ name => 'PomBase' });

  $pombase_dbs{feature_cvtermprop_type} = $pombase_db;
  $pombase_dbs{feature_relationshipprop_type} = $pombase_db;
  $pombase_dbs{$go_cv_map{P}} = $pombase_db;
  $pombase_dbs{$go_cv_map{F}} = $pombase_db;
  $pombase_dbs{$go_cv_map{C}} = $pombase_db;

  $self->objs()->{pombase_dbs} = \%pombase_dbs;

  my $cv_rs = $chado->resultset('Cv::Cv');

  $self->objs()->{feature_cvtermprop_type_cv} =
    $cv_rs->create({ name => 'feature_cvtermprop_type' });
  $self->objs()->{feature_relationshipprop_type_cv} =
    $cv_rs->create({ name => 'feature_relationshipprop_type' });

  $self->objs()->{genedb_literature_cv} =
    $cv_rs->find({ name => 'genedb_literature' });

  my $cvterm_rs = $chado->resultset('Cv::Cvterm');

  $self->objs()->{unfetched_pub_cvterm} =
    $cvterm_rs->find({ name => 'unfetched',
                       cv_id => $self->objs()->{genedb_literature_cv}->cv_id() });


  for my $extra_cv_name (keys %{$self->objs()->{cv_alt_names}}) {
    $cv_rs->create({ name => $extra_cv_name });

    if (!defined $self->objs()->{pombase_dbs}->{$extra_cv_name}) {
      $self->objs()->{pombase_dbs}->{$extra_cv_name} = $pombase_db;
    }
  }

  $self->objs()->{null_pub} =
    $chado->resultset('Pub::Pub')->find({ uniquename => 'null' });

  $self->objs()->{orthologous_to_cvterm} =
    $chado->resultset('Cv::Cvterm')->find({ name => 'orthologous_to' });


  $self->objs()->{synonym_type_cv} = $self->find_cv_by_name('synonym_type');

  $self->objs()->{exact_cvterm} =
    $self->find_cvterm($self->objs()->{synonym_type_cv}, 'exact');
}


method find_cv_by_name($cv_name) {
  die 'no $cv_name' unless defined $cv_name;

  return ($self->chado()->resultset('Cv::Cv')->find({ name => $cv_name })
    or die "no cv with name: $cv_name");
}
memoize ('find_cv_by_name');


method find_db_by_name($db_name) {
  die 'no $db_name' unless defined $db_name;

  return ($self->chado()->resultset('General::Db')->find({ name => $db_name })
    or die "no db with name: $db_name");
}
memoize ('find_db_by_name');


my %new_cvterm_ids = ();

# return an ID for a new term in the CV with the given name
method get_dbxref_id($db_name) {
  if (!exists $new_cvterm_ids{$db_name}) {
    $new_cvterm_ids{$db_name} = 1;
  }

  return $new_cvterm_ids{$db_name}++;
}


method find_pub($identifier) {
  my $pub_rs = $self->chado()->resultset('Pub::Pub');

  return $pub_rs->find({ uniquename => $identifier });
}


method find_cvterm($cv, $term_name, %options) {
  warn "    _find_cvterm('", $cv->name(), "', '$term_name')\n" if $self->verbose();

  my %search_options = ();

  if ($options{prefetch_dbxref}) {
    $search_options{prefetch} = { dbxref => 'db' };
  }

  my $cvterm_rs = $self->chado()->resultset('Cv::Cvterm');
  my $cvterm = $cvterm_rs->find({ name => $term_name, cv_id => $cv->cv_id() },
                                { %search_options });

  if (defined $cvterm) {
    return $cvterm;
  } else {
    my $synonym_rs = $self->chado()->resultset('Cv::Cvtermsynonym');
    my $search_rs =
      $synonym_rs->search({ synonym => $term_name,
                            type_id => $self->objs()->{exact_cvterm}->cvterm_id() });

    if ($search_rs->count() > 1) {
      die "more than one cvtermsynonym found for $term_name";
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
#memoize ('find_cvterm');


method find_or_create_cvterm($cv, $term_name) {
  my $cvterm = $self->find_cvterm($cv, $term_name);

  # nested transaction
  my $cvterm_guard = $self->chado()->txn_scope_guard();

  if (defined $cvterm) {
    warn "    found cvterm_idp ", $cvterm->cvterm_id(),
      " when looking for $term_name in ", $cv->name(),"\n" if $self->verbose();
  } else {
    warn "    failed to find: $term_name in ", $cv->name(), "\n" if $self->verbose();

    my $db = $self->objs()->{pombase_dbs}->{$cv->name()};
    if (!defined $db) {
      die "no database for cv: ", $cv->name();
    }

    my $new_ont_id = $self->get_dbxref_id($db->name());
    my $formatted_id = sprintf "%07d", $new_ont_id;

    my $dbxref_rs = $self->chado()->resultset('General::Dbxref');

    die "no db for ", $cv->name(), "\n" if !defined $db;

    warn "    creating dbxref $formatted_id, ", $cv->name(), "\n" if $self->verbose();

    my $dbxref =
      $dbxref_rs->create({ db_id => $db->db_id(),
                           accession => $formatted_id });

    my $cvterm_rs = $self->chado()->resultset('Cv::Cvterm');
    $cvterm = $cvterm_rs->create({ name => $term_name,
                                   dbxref_id => $dbxref->dbxref_id(),
                                   cv_id => $cv->cv_id() });

    warn "    created new cvterm, id: ", $cvterm->cvterm_id(), "\n" if $self->verbose();
  }

  $cvterm_guard->commit();

  return $cvterm;
}
memoize ('find_or_create_cvterm');


my %stored_cvterms = ();

method create_feature_cvterm($pombe_gene, $cvterm, $pub, $is_not) {
  my $rs = $self->chado()->resultset('Sequence::FeatureCvterm');

  my $systematic_id = $pombe_gene->uniquename();

  if (!exists $stored_cvterms{$cvterm->name()}{$systematic_id}{$pub->uniquename()}) {
    $stored_cvterms{$cvterm->name()}{$systematic_id}{$pub->uniquename()} = 0;
  }

  my $rank =
    $stored_cvterms{$cvterm->name()}{$systematic_id}{$pub->uniquename()}++;

  return $rs->create({ feature_id => $pombe_gene->feature_id(),
                       cvterm_id => $cvterm->cvterm_id(),
                       pub_id => $pub->pub_id(),
                       is_not => $is_not,
                       rank => $rank });
}

method add_feature_cvtermprop($feature_cvterm, $name, $value, $rank) {
  if (!defined $name) {
    die "no name for property\n";
  }
  if (!defined $value) {
    die "no value for $name\n";
  }

  if (!defined $rank) {
    $rank = 0;
  }

  if (ref $value eq 'ARRAY') {
    my @ret = ();
    for (my $i = 0; $i < @$value; $i++) {
      push @ret, $self->add_feature_cvtermprop($feature_cvterm,
                                               $name, $value->[$i], $i);
    }
    return @ret;
  }

  my $type = $self->find_or_create_cvterm($self->objs()->{feature_cvtermprop_type_cv},
                                          $name);

  my $rs = $self->chado()->resultset('Sequence::FeatureCvtermprop');

  warn "    adding feature_cvtermprop $name => $value\n" if $self->verbose();

  return $rs->create({ feature_cvterm_id =>
                         $feature_cvterm->feature_cvterm_id(),
                       type_id => $type->cvterm_id(),
                       value => $value,
                       rank => $rank });
}

method add_feature_relationshipprop($feature_relationship, $name, $value) {
  if (!defined $name) {
    die "no name for property\n";
  }
  if (!defined $value) {
    die "no value for $name\n";
  }

  my $type = $self->find_or_create_cvterm($self->objs()->{feature_relationshipprop_type_cv},
                                          $name);

  my $rs = $self->chado()->resultset('Sequence::FeatureRelationshipprop');

  warn "    adding feature_relationshipprop $name => $value\n" if $self->verbose();

  return $rs->create({ feature_relationship_id =>
                         $feature_relationship->feature_relationship_id(),
                       type_id => $type->cvterm_id(),
                       value => $value,
                       rank => 0 });
}

method is_go_cv_name($cv_name) {
  return grep { $_ eq $cv_name } values %go_cv_map;
}

method get_and_check_date($sub_qual_map) {
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


method find_or_create_dbxref($db, $accession) {
  my $dbxref_rs = $self->chado()->resultset('General::Dbxref');
  return $dbxref_rs->find_or_create({ db_id => $db->db_id(),
                                      accession => $accession });
}


method get_pub_from_db_xref($term, $db_xref) {
  if (defined $db_xref) {
    if ($db_xref =~ /^((.*):(.*))/) {
      my $db_name = $2;
      my $accession = $3;

      my $db = $self->find_db_by_name($db_name);

      warn "    finding pub for $db_xref\n" if $self->verbose();

      my $pub = $self->find_pub($db_xref);

      if (!defined $pub) {

        warn "    pub not found for: $db_xref  ($db);\n" if $self->verbose();

        my $pub_rs = $self->chado()->resultset('Pub::Pub');
        $pub = $pub_rs->create({
          uniquename => $db_xref,
          type_id => $self->objs()->{unfetched_pub_cvterm}->cvterm_id()
        });
        my $dbxref = $self->find_or_create_dbxref($db, $accession);
        my $pub_dbxref_rs = $self->chado()->resultset('Pub::PubDbxref');
        $pub_dbxref_rs->create({ pub_id => $pub->pub_id(),
                                 dbxref_id => $dbxref->dbxref_id() });
        warn "    created new dbxref and pub for: $db_xref\n" if $self->verbose();
      }

      warn "    using existing dbxref and pub for: $db_xref\n" if $self->verbose();

      return $pub;
    } else {
      warn "    qualifier for $term",
        " has unknown format db_xref (", $db_xref,
          ") - using null publication\n" unless $self->verbose() == 10;
      return $self->objs()->{null_pub};
    }
  } else {
    warn "    qualifier for $term",
      " has no db_xref - using null publication\n" unless $self->verbose() == 10;
    return $self->objs()->{null_pub};
  }

}

method add_term_to_gene($pombe_gene, $cv_name, $term, $sub_qual_map,
                       $create_cvterm) {
  my $cv = $self->find_cv_by_name($cv_name);

  my $db_accession;

  if ($self->is_go_cv_name($cv_name)) {
    $db_accession = delete $sub_qual_map->{GOid};
    if (!defined $db_accession) {
      my $systematic_id = $pombe_gene->uniquename();
      warn "  no GOid for $systematic_id annotation $term\n";
    }
    if ($db_accession !~ /GO:(.*)/) {
      my $systematic_id = $pombe_gene->uniquename();
      warn "  GOid doesn't start with 'GO:' for $systematic_id: $db_accession\n";
    }
  }

  my $cvterm;

  if ($create_cvterm) {
    $cvterm = $self->find_or_create_cvterm($cv, $term, $db_accession);
  } else {
    $cvterm = $self->find_cvterm($cv, $term, prefetch_dbxref => 1);

    if (!defined $cvterm) {
      die "can't find cvterm of $term";
    }
  }

  if (defined $db_accession) {
    if ($db_accession =~ /(.*):(.*)/) {
      my $new_db_name = $1;
      my $new_dbxref_accession = $2;

      my $dbxref = $cvterm->dbxref();
      my $db = $dbxref->db();

      if ($new_db_name ne $db->name()) {
        die "database name for new term ($new_db_name) doesn't match " .
          "existing name (" . $db->name() . ") for term name: $term";
      }

      if ($new_dbxref_accession ne $dbxref->accession()) {
        die "database accession for new term ($new_dbxref_accession) " .
          "doesn't match existing name (" . $dbxref->accession() .
            ") for term name: $term";
      }
    } else {
      die "database ID ($db_accession) doesn't contain a colon";
    }
  }

  my $db_xref = delete $sub_qual_map->{db_xref};

  my $pub = $self->get_pub_from_db_xref($term, $db_xref);

  my $qualifier = delete $sub_qual_map->{qualifier};

  my $is_not = 0;

  if (defined $qualifier && $qualifier eq 'NOT') {
    $is_not = 1;
    $qualifier = undef;
  }

  my $featurecvterm =
    $self->create_feature_cvterm($pombe_gene, $cvterm, $pub, $is_not);

  if ($self->is_go_cv_name($cv_name)) {
    my $evidence_code = delete $sub_qual_map->{evidence};

    my $evidence;

    if (defined $evidence_code) {
      $evidence = $self->objs()->{go_evidence_codes}->{$evidence_code};
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
    $self->add_feature_cvtermprop($featurecvterm,
                                  evidence => $evidence);

    if (defined $sub_qual_map->{residue}) {
      $self->add_feature_cvtermprop($featurecvterm,
                                    residue => delete $sub_qual_map->{residue});
    }
  }

  if (defined $qualifier) {
    $self->add_feature_cvtermprop($featurecvterm, qualifier => $qualifier);
  }

  my $date = $self->get_and_check_date($sub_qual_map);
  if (defined $date) {
    $self->add_feature_cvtermprop($featurecvterm, date => $date);
  }

}

method split_sub_qualifiers($cc_qualifier) {
  my %map = ();

  my @bits = split /;/, $cc_qualifier;

  for my $bit (@bits) {
    if ($bit =~ /\s*([^=]+?)\s*=\s*(.*?)\s*$/) {
      my $name = $1;
      my $value = $2;
      if (exists $map{$name}) {
        die "duplicated sub-qualifier '$name' from:
/controlled_curation=\"$cc_qualifier\"";
      }

      # if true ".. from=foo|bar" will create two qualifiers rather than one
      my $split_piped_qualifiers = 0;

      if ($split_piped_qualifiers) {
        my @bits = split /\|/, $value;

        if (@bits > 1) {
          $value = [@bits];
        }
      }

      $map{$name} = $value;

      if ($name =~ / /) {
        warn "  qualifier name ('$name') contains a space\n" unless $self->verbose() == 10;
      }

      if ($name eq 'cv' && $value =~ / /) {
        warn "  cv name ('$value') contains a space\n" unless $self->verbose() == 10;
      }

      if ($name eq 'db_xref' && $value =~ /\|/) {
        warn "  annotation should be split into two qualifier: $name=$value\n";
      }
    }
  }

  return %map;
}

method add_feature_relationship_pub($relationship, $pub) {
  my $rs = $self->chado()->resultset('Sequence::FeatureRelationshipPub');

  warn "    adding pub ", $pub->pub_id(), " to feature_relationship ",
    $relationship->feature_relationship_id() , "\n" if $self->verbose();

  return $rs->create({ feature_relationship_id =>
                         $relationship->feature_relationship_id(),
                       pub_id => $pub->pub_id() });

}



method process_ortholog($pombe_gene, $term, $sub_qual_map) {
  my $org_name;
  my $gene_bit;

  my $date = delete $sub_qual_map->{date};

  if ($term =~ /^orthologous to S\. cerevisiae (.*)/) {
    $gene_bit = $1;
  } else {
    if ($term =~ /^human\s+(.*?)\s+ortholog$/) {
      $gene_bit = $1;
    } else {
      warn "    not recognised as an ortholog curation: $term\n" if $self->verbose();
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
    warn "    creating ortholog from ", $pombe_gene->uniquename(),
      " to $ortholog_name\n" if $self->verbose();

    my $ortholog_feature = undef;
    try {
      $ortholog_feature = $self->find_chado_feature($ortholog_name, 1);
    };

    if (!defined $ortholog_feature) {
      warn "  ortholog ($ortholog_name) not found\n";
      return 0;
    }

    my $rel_rs = $self->chado()->resultset('Sequence::FeatureRelationship');

    try {
      my $orth_guard = $self->chado()->txn_scope_guard;
      my $rel = $rel_rs->create({ object_id => $pombe_gene->feature_id(),
                                  subject_id => $ortholog_feature->feature_id(),
                                  type_id => $self->objs()->{orthologous_to_cvterm}->cvterm_id()
                                });
      $self->add_feature_relationshipprop($rel, 'date', $date);
      my $db_xref = delete $sub_qual_map->{db_xref};
      my $pub = $self->get_pub_from_db_xref($term, $db_xref);
      $self->add_feature_relationship_pub($rel, $pub);
      $orth_guard->commit();
    } catch {
      warn "  failed to create ortholog relation: $_\n";
      return 0;
    };
  }

  return 1;
}


method process_one_cc($pombe_gene, $bioperl_feature, $qualifier) {
  my $systematic_id = $pombe_gene->uniquename();

  warn "    process_one_cc($systematic_id, $bioperl_feature, '$qualifier')\n"
    if $self->verbose();

  my %qual_map = ();

  try {
    %qual_map = $self->split_sub_qualifiers($qualifier);
  } catch {
    warn "  $_: failed to process sub-qualifiers from $qualifier, feature:\n";
    $self->dump_feature($bioperl_feature);
  };

  if (scalar(keys %qual_map) == 0) {
    return ();
  }

  my $cv_name = delete $qual_map{cv};
  my $term = delete $qual_map{term};

  if (!defined $term || length $term == 0) {
    warn "  no term for: $qualifier\n";
    return ();
  }

  if (!defined $cv_name) {
    map {
      my $long_name = $_;

      if ($term =~ s/$long_name, *//) {
        my $short_cv_name = $self->chado()->{cv_long_names}->{$long_name};
        $cv_name = $short_cv_name;
      }
    } keys %{$self->objs()->{cv_long_names}};
  }

  if (defined $cv_name) {
    $term =~ s/$cv_name, *//;

    if (exists $self->objs()->{cv_alt_names}->{$cv_name}) {
      map { $term =~ s/$_, *//; } @{$self->objs()->{cv_alt_names}->{$cv_name}};
    }

    if (grep { $_ eq $cv_name } keys %{$self->objs()->{cv_alt_names}}) {
      try {
        $self->add_term_to_gene($pombe_gene, $cv_name, $term, \%qual_map, 1);
      } catch {
        warn "    $_: failed to load qualifier '$qualifier' from $systematic_id\n";
        $self->dump_feature($bioperl_feature) if $self->verbose();
      };
      warn "    loaded: $qualifier\n" if $self->verbose();
    } else {
      warn "  unknown cv $cv_name: $qualifier\n";
    }
  } else {
    if (!$self->process_ortholog($pombe_gene, $term, \%qual_map)) {
      warn "  didn't process: $qualifier\n";
      return ();
    }
  }

  return %qual_map;
}

method process_one_go_qual($pombe_gene, $bioperl_feature, $qualifier) {
  warn "    go qualifier: $qualifier\n" if $self->verbose();

  my %qual_map = ();

  try {
    %qual_map = $self->split_sub_qualifiers($qualifier);
  } catch {
    warn "  $_: failed to process sub-qualifiers from $qualifier, feature:\n";
    $self->dump_feature($bioperl_feature);
  };

  if (scalar(keys %qual_map) == 0) {
    return ();
  }

  my $aspect = delete $qual_map{aspect};

  if (defined $aspect) {
    my $cv_name = $self->get_go_cv_map()->{uc $aspect};

    my $term = delete $qual_map{term};

    try {
      $self->add_term_to_gene($pombe_gene, $cv_name, $term, \%qual_map, 0);
    } catch {
      my $systematic_id = $pombe_gene->uniquename();
      warn "  $_: failed to load qualifier '$qualifier' from $systematic_id:\n";
      $self->dump_feature($bioperl_feature) if $self->verbose();
      return ();
    };
    warn "    loaded: $qualifier\n" if $self->verbose();
  } else {
    warn "  no aspect for: $qualifier\n";
    return ();
  }

  return %qual_map;
}

method check_unused_quals
{
  return if $self->verbose() == 10;

  my $qual_text = shift;
  my %quals = @_;

  if (scalar(keys %quals) > 0) {
    warn "  unprocessed sub qualifiers:\n";
    while (my ($key, $value) = each %quals) {
      warn "   $key => $value\n";
    }
  }
}

1;
