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
use Carp qw(cluck);

use Moose;

use Memoize;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::FeatureDumper';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::ChadoObj';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::QualifierSplitter';

has verbose => (is => 'ro', isa => 'Bool');

method find_cv_by_name($cv_name) {
  die 'no $cv_name' unless defined $cv_name;

  return ($self->chado()->resultset('Cv::Cv')->find({ name => $cv_name })
    or die "no cv with name: $cv_name");
}
memoize ('find_cv_by_name');

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

# look up cvterm by $embl_term_name first, then by GOid, complain
# about mismatches
method add_term_to_gene($pombe_feature, $cv_name, $embl_term_name, $sub_qual_map,
                        $create_cvterm) {
  $embl_term_name =~ s/\s+/ /g;

  my $mapping_conf = $self->config()->{mappings}->{$cv_name};

  if (defined $mapping_conf) {
    $cv_name = $mapping_conf->{new_name};

    my $mapping = $mapping_conf->{mapping};
    my $new_term_id = $mapping->{$embl_term_name};

    if (!defined $new_term_id) {
      die "can't find new term for $embl_term_name in mapping for $cv_name\n";
    }

    my $new_term = $self->find_cvterm_by_term_id($new_term_id);

    if (!defined $new_term) {
      die "can't find '$new_term_id' in $cv_name\n";
    }

    if ($self->verbose()) {
      print "mapping $embl_term_name to $cv_name/", $new_term->name(), "\n";
    }

    $embl_term_name = $new_term->name();
  }

  my $cv = $self->find_cv_by_name($cv_name);

  my $uniquename = $pombe_feature->uniquename();

  my $qualifier_term_id;

  if ($self->is_go_cv_name($cv_name)) {
    $qualifier_term_id = delete $sub_qual_map->{GOid};
    if (!defined $qualifier_term_id) {
      warn "  no GOid for $uniquename annotation: '$embl_term_name'\n";
      return;
    }
    if ($qualifier_term_id !~ /GO:(.*)/) {
      warn "  GOid doesn't start with 'GO:' for $uniquename: $qualifier_term_id\n";
    }
  }

  my $cvterm;

  my $obsolete_id;

  if (defined $qualifier_term_id) {
    $obsolete_id = $self->config()->{obsolete_term_mapping}->{$qualifier_term_id};
  }

  if ($create_cvterm) {
    $cvterm = $self->find_or_create_cvterm($cv, $embl_term_name, $qualifier_term_id);
  } else {
    $cvterm = $self->find_cvterm_by_name($cv, $embl_term_name, prefetch_dbxref => 1);

    if (!defined $cvterm) {
      if (defined $obsolete_id) {
        $cvterm = $self->find_cvterm_by_name($cv, "$embl_term_name (obsolete $obsolete_id)",
                                             prefetch_dbxref => 1);
      }
      if (!defined $cvterm) {
        $cvterm = $self->find_cvterm_by_term_id($qualifier_term_id);
        if (!defined $cvterm) {
          die qq(unknown term name "$embl_term_name" and unknown GO ID "$qualifier_term_id"\n);
        }
        if (!$self->config()->{allowed_unknown_term_names}->{$qualifier_term_id}) {
          die "found cvterm by ID, but name doesn't match any cvterm: $qualifier_term_id " .
            "EMBL file: $embl_term_name  Chado name for ID: ", $cvterm->name(), "\n";
        }
        $qualifier_term_id = undef;
      }
    }
  }

  if (defined $qualifier_term_id) {
    if ($qualifier_term_id =~ /(.*):(.*)/) {
      my $new_db_name = $1;
      my $new_dbxref_accession = $2;

      my $dbxref = $cvterm->dbxref();
      my $db = $dbxref->db();

      if ($new_db_name ne $db->name()) {
        die "database name for new term ($new_db_name) doesn't match " .
          "existing name (" . $db->name() . ") for term name: $embl_term_name\n";
      }

      if ($new_dbxref_accession ne $dbxref->accession()) {
        my $allowed_mismatch_confs =
          $self->config()->{allowed_term_mismatches}->{$uniquename};

        if (!defined $allowed_mismatch_confs) {
          (my $key = $uniquename) =~ s/\.\d+$//;
          $allowed_mismatch_confs =
            $self->config()->{allowed_term_mismatches}->{$key};
        }

        my $allowed_mismatch_type = undef;
        if (defined $allowed_mismatch_confs &&
            grep {
              my $res =
                $_->{embl_id} eq $qualifier_term_id &&
                $_->{embl_name} eq $embl_term_name;
              if ($res) {
                $allowed_mismatch_type = $_->{winner};
              }
              $res;
            } @{$allowed_mismatch_confs}) {
          if ($allowed_mismatch_type eq 'ID') {
            $cvterm = $self->find_cvterm_by_term_id($qualifier_term_id);
          } else {
            if ($allowed_mismatch_type eq 'name') {
              # this is the default - fall through
            } else {
              die "unknown mismatch type: $allowed_mismatch_type\n";
            }
          }
        } else {
          my $db_term_id = $db->name() . ":" . $dbxref->accession();
          my $embl_cvterm =
            $self->find_cvterm_by_term_id($qualifier_term_id);
          if (defined $obsolete_id && $db_term_id eq $obsolete_id) {
            # use the cvterm we got from the GOid, not the name
            $cvterm = $embl_cvterm;
          } else {
            die "ID in EMBL file ($qualifier_term_id) " .
              "doesn't match ID in Chado ($db_term_id) " .
              "for EMBL term name $embl_term_name   (Chado term name: ",
              $embl_cvterm->name(), ")\n";
          }
        }
      }
    } else {
      die "database ID ($qualifier_term_id) doesn't contain a colon";
    }
  }

  my $db_xref = delete $sub_qual_map->{db_xref};
  my $pub = $self->get_pub_from_db_xref($embl_term_name, $db_xref);

  my $is_not = 0;

  my $qualifiers = delete $sub_qual_map->{qualifier};
  my @qualifiers = ();

  if (defined $qualifiers) {
    @qualifiers =
      grep {
        if ($_ eq 'NOT') {
          $is_not = 1;
          0;
        } else {
          1;
        }
      } @$qualifiers;
  }

  my $featurecvterm =
    $self->create_feature_cvterm($pombe_feature, $cvterm, $pub, $is_not);

  if ($self->is_go_cv_name($cv_name)) {
    $self->maybe_move_igi($qualifiers, $sub_qual_map);

    if (defined $sub_qual_map->{with}) {
      my @withs = split /\|/, delete $sub_qual_map->{with};
      for (my $i = 0; $i < @withs; $i++) {
        my $with = $withs[$i];
        $self->add_feature_cvtermprop($featurecvterm, with => $with, $i);
      }
    }
    if (defined $sub_qual_map->{from}) {
      my @froms = split /\|/, delete $sub_qual_map->{from};
      for (my $i = 0; $i < @froms; $i++) {
        my $from = $froms[$i];
        $self->add_feature_cvtermprop($featurecvterm, from => $from, $i);
      }
    }
  }

  $self->add_feature_cvtermprop($featurecvterm, qualifier => [@qualifiers]);

  my $evidence_code = delete $sub_qual_map->{evidence};
  my $evidence = undef;

  if (defined $evidence_code) {
    $evidence = $self->config()->{evidence_types}->{$evidence_code}->{name};
    if (!grep { $_ eq $cv_name } ('biological_process', 'molecular_function',
                                  'cellular_component')) {
      warn "found evidence for $embl_term_name in $cv_name\n";
    }
  } else {
    if (grep { $_ eq $cv_name } ('biological_process', 'molecular_function',
                                 'cellular_component')) {
      warn "no evidence for $cv_name annotation: $embl_term_name in ", $pombe_feature->uniquename(), "\n";
    }
  }
  if (defined $evidence_code) {
    if (!defined $evidence) {
      warn "no evidence description for $evidence_code\n";
    }

    $self->add_feature_cvtermprop($featurecvterm, evidence => $evidence);
  }

  if (defined $sub_qual_map->{residue}) {
    $self->add_feature_cvtermprop($featurecvterm,
                                  residue => delete $sub_qual_map->{residue});
  }

  if (defined $sub_qual_map->{allele}) {
    $self->add_feature_cvtermprop($featurecvterm,
                                  allele => delete $sub_qual_map->{allele});
  }

  my $date = $self->get_and_check_date($sub_qual_map);
  if (defined $date) {
    $self->add_feature_cvtermprop($featurecvterm, date => $date);
  }

  if ($sub_qual_map->{annotation_extension}) {
    push @{$self->config()->{post_process}->{$featurecvterm->feature_cvterm_id()}}, {
      feature_cvterm => $featurecvterm,
      qualifiers => $sub_qual_map,
    }
  }

  return 1;
}

method maybe_move_igi($qualifiers, $sub_qual_map) {
  if ($sub_qual_map->{evidence} && $sub_qual_map->{evidence} eq 'IGI' &&
      defined $qualifiers && @{$qualifiers} > 0 &&
      $qualifiers->[0] eq 'localization_dependency') {
    if (exists $sub_qual_map->{with}) {
      my $with = delete $sub_qual_map->{with};

      if (exists $sub_qual_map->{annotation_extension}) {
        warn "annotation_extension already existing when converting IGI\n";
      } else {
        $sub_qual_map->{annotation_extension} = "localizes($with)";
      }
    } else {
      warn "no 'with' qualifier on localization_dependency IGI\n"
    }
  }
}

method add_feature_relationship_pub($relationship, $pub) {
  my $rs = $self->chado()->resultset('Sequence::FeatureRelationshipPub');

  warn "    adding pub ", $pub->pub_id(), " to feature_relationship ",
    $relationship->feature_relationship_id() , "\n" if $self->verbose();

  return $rs->create({ feature_relationship_id =>
                         $relationship->feature_relationship_id(),
                       pub_id => $pub->pub_id() });

}

method process_ortholog($chado_object, $term, $sub_qual_map) {
  warn "    process_ortholog()\n" if $self->verbose();
  my $org_name;
  my $gene_bit;

  my $chado_object_type = $chado_object->type()->name();
  my $chado_object_uniquename = $chado_object->uniquename();

  if ($chado_object_type ne 'gene' && $chado_object_type ne 'pseudogene') {
    warn "  can't apply ortholog to $chado_object_type: $term\n" if $self->verbose();
    return 0;
  }

  my $organism_common_name;

  if ($term =~ /^orthologous to S\. cerevisiae (.*)/) {
    $organism_common_name = 'Scerevisiae';
    $gene_bit = $1;
  } else {
    if ($term =~ /^human\s+(.*?)\s+ortholog$/) {
      $organism_common_name = 'human';
      $gene_bit = $1;
    } else {
      warn "  didn't find ortholog in: $term\n" if $self->verbose();
      return 0;
    }
  }

  my $organism = $self->find_organism_by_common_name($organism_common_name);

  my @gene_names = ();

  for my $gene_name (split /\s+and\s+/, $gene_bit) {
    if ($gene_name =~ /^(\S+)(?:\s+\(([cn])-term\))?$/i) {
      push @gene_names, { name => $1, term => $2 };
    } else {
      warn qq(gene name contains whitespace "$gene_name" from "$term");
      return 0;
    }
  }

  my $date = $self->get_and_check_date($sub_qual_map);

  for my $ortholog_conf (@gene_names) {
    my $ortholog_name = $ortholog_conf->{name};
    my $ortholog_term = $ortholog_conf->{term};

    warn "    creating ortholog from ", $chado_object_uniquename,
      " to $ortholog_name\n" if $self->verbose();

    my $ortholog_feature = undef;
    try {
      $ortholog_feature =
        $self->find_chado_feature($ortholog_name, 1, 1, $organism);
    } catch {
      warn "  caught exception: $_\n";
    };

    if (!defined $ortholog_feature) {
      warn "ortholog ($ortholog_name) not found\n";
      next;
    }

    my $rel_rs = $self->chado()->resultset('Sequence::FeatureRelationship');

    try {
      my $orth_guard = $self->chado()->txn_scope_guard;
      my $rel = $rel_rs->create({ object_id => $chado_object->feature_id(),
                                  subject_id => $ortholog_feature->feature_id(),
                                  type_id => $self->objs()->{orthologous_to_cvterm}->cvterm_id()
                                });

      if (defined $date) {
        $self->add_feature_relationshipprop($rel, date => $date);
      }

      my $db_xref = delete $sub_qual_map->{db_xref};
      my $pub = $self->get_pub_from_db_xref($term, $db_xref);
      $self->add_feature_relationship_pub($rel, $pub);
      if (defined $ortholog_term) {
        $self->add_feature_relationshipprop($rel, 'subject terminus', $ortholog_term);
      }
      $orth_guard->commit();
      warn "  created ortholog to $ortholog_name\n" if $self->verbose();
    } catch {
      warn "  failed to create ortholog relation from $chado_object_uniquename " .
        "to $ortholog_name: $_\n";
      return 0;
    };
  }

  return 1;
}

method process_paralog($chado_object, $term, $sub_qual_map) {
  warn "    process_ortholog()\n" if $self->verbose();
  my $other_gene;

  my $chado_object_type = $chado_object->type()->name();
  my $chado_object_uniquename = $chado_object->uniquename();

  if ($chado_object_type ne 'gene' && $chado_object_type ne 'pseudogene') {
    warn "  can't apply paralog to $chado_object_type: $term\n" if $self->verbose();
    return 0;
  }

  my $related;

  if ($term =~ /^(paralogous|similar|related) to S\. pombe (.*)/i) {
    if ($1 eq 'related') {
      $related = 1;
    } else {
      $related = 0;
    }
    my @other_gene_bits = split / and /, $2;

    my $date = $self->get_and_check_date($sub_qual_map);

    push @{$self->config()->{paralogs}->{$chado_object_uniquename}}, {
      other_gene_names => [@other_gene_bits],
      feature => $chado_object,
      related => $related,
      date => $date,
    };

    return 1;
  } else {
    warn "  didn't find paralog in: $term\n" if $self->verbose();
    return 0;
  }
}

method process_warning($chado_object, $term, $sub_qual_map)
{
  my $chado_object_type = $chado_object->type()->name();

  warn "    process_warning()\n" if $self->verbose();
  if ($chado_object_type ne 'gene' and $chado_object_type ne 'pseudogene') {
    return 0;
  }

  if ($term =~ /WARNING: (.*)/) {
    $self->add_term_to_gene($chado_object, 'warning', $1,
                            $sub_qual_map, 1);
    return 1;
  } else {
    return 0;
  }
}

method process_family($chado_object, $term, $sub_qual_map)
{
  warn "    process_family()\n" if $self->verbose();
  $self->add_term_to_gene($chado_object, 'PomBase family or domain', $term,
                          $sub_qual_map, 1);
  return 1;
}

method process_one_cc($chado_object, $bioperl_feature, $qualifier,
                      $target_curations) {
  my $systematic_id = $chado_object->uniquename();

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
  my $cv_name_qual_exists = defined $cv_name;
  my $term = delete $qual_map{term};

  if (!defined $term || length $term == 0) {
    warn "no term for: $qualifier\n" if $self->verbose();
    return ();
  }

  if (!defined $cv_name) {
    map {
      my $long_name = $_;

      if ($term =~ s/^$long_name, *//) {
        my $short_cv_name = $self->objs()->{cv_long_names}->{$long_name};
        $cv_name = $short_cv_name;
      }
    } keys %{$self->objs()->{cv_long_names}};
  }

  my $chado_object_type = $chado_object->type()->name();

  if ($cv_name_qual_exists) {
    if (!($term =~ s/$cv_name, *//)) {

      (my $space_cv_name = $cv_name) =~ s/_/ /g;

      if (!($term =~ s/$space_cv_name, *//)) {
        my $name_substituted = 0;

        if (exists $self->objs()->{cv_alt_names}->{$cv_name}) {
          for my $alt_name (@{$self->objs()->{cv_alt_names}->{$cv_name}}) {
            if ($term =~ s/^$alt_name, *//) {
              $name_substituted = 1;
              last;
            }
            $alt_name =~ s/_/ /g;
            if ($term =~ s/^$alt_name, *//) {
              $name_substituted = 1;
              last;
            }
          }
        }

        if (!$name_substituted) {
          if ($term =~ /(.*?),/) {
            my $cv_name_in_term = $1;
            if ($cv_name_in_term ne $cv_name) {
              if ($chado_object_type ne 'gene' and $chado_object_type ne 'pseudogene') {
                warn qq{cv_name ("$cv_name") doesn't match start of term ("$cv_name_in_term")\n};
              }
            }
          }
        }
      }
    }
  }

  if (defined $cv_name) {
    if (grep { $_ eq $cv_name } keys %{$self->objs()->{cv_alt_names}}) {
      if ($self->objs()->{gene_cvs}->{$cv_name} xor
          ($chado_object_type eq 'gene' or $chado_object_type eq 'pseudogene')) {
        return ();
      }
      try {
        $self->add_term_to_gene($chado_object, $cv_name, $term, \%qual_map, 1);
      } catch {
        warn "$_: failed to load qualifier '$qualifier' from $systematic_id\n";
        $self->dump_feature($bioperl_feature) if $self->verbose();
        return ();
      };
      warn "    loaded: $qualifier\n" if $self->verbose();
    } else {
      warn "CV name not recognised: $qualifier\n";
      return ();
    }
  } else {
      if (!$self->process_ortholog($chado_object, $term, \%qual_map)) {
        if (!$self->process_paralog($chado_object, $term, \%qual_map)) {
          if (!$self->process_warning($chado_object, $term, \%qual_map)) {
            if (!$self->process_family($chado_object, $term, \%qual_map)) {
              warn "qualifier not recognised: $qualifier\n";
              return ();
            }
          }
        }
      }
  }

  $self->check_unused_quals($qualifier, %qual_map);

  return %qual_map;
}

method process_one_go_qual($chado_object, $bioperl_feature, $qualifier) {
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
      $self->add_term_to_gene($chado_object, $cv_name, $term, \%qual_map, 0);
      $self->check_unused_quals($qualifier, %qual_map);
    } catch {
      my $systematic_id = $chado_object->uniquename();
      warn "$_: failed to load qualifier '$qualifier' from $systematic_id:\n";
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

method process_product($chado_feature, $product)
{
  $self->add_term_to_gene($chado_feature, 'PomBase gene products',
                          $product, {}, 1);
}

method check_unused_quals
{
  my $qual_text = shift;
  my %quals = @_;

  if (scalar(keys %quals) > 0) {
    warn "  unprocessed sub qualifiers:\n" if $self->verbose();
    while (my ($key, $value) = each %quals) {
      $self->config()->{stats}->{unused_qualifiers}->{$key}++;
      warn "   $key => $value\n" if $self->verbose();
    }
  }
}

1;
