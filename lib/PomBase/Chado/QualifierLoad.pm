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
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::ChadoObj';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';

has verbose => (is => 'ro', isa => 'Bool');

method find_cv_by_name($cv_name) {
  die 'no $cv_name' unless defined $cv_name;

  return ($self->chado()->resultset('Cv::Cv')->find({ name => $cv_name })
    or die "no cv with name: $cv_name");
}
memoize ('find_cv_by_name');


my %new_cvterm_ids = ();

# return an ID for a new term in the CV with the given name
method get_dbxref_id($db_name) {
  if (!exists $new_cvterm_ids{$db_name}) {
    $new_cvterm_ids{$db_name} = 1;
  }

  return $new_cvterm_ids{$db_name}++;
}



method find_or_create_cvterm($cv, $term_name) {
  my $cvterm = $self->find_cvterm_by_name($cv, $term_name);

  # nested transaction
  my $cvterm_guard = $self->chado()->txn_scope_guard();

  if (defined $cvterm) {
    warn "    found cvterm_idp ", $cvterm->cvterm_id(),
      " when looking for $term_name in ", $cv->name(),"\n" if $self->verbose();
  } else {
    warn "    failed to find: $term_name in ", $cv->name(), "\n" if $self->verbose();

    my $db = $self->objs()->{dbs_objects}->{$cv->name()};
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

  my $type = $self->find_or_create_cvterm($self->get_cv('feature_cvtermprop_type'),
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
        if (!$self->config()->{allowed_unknown_term_names}->{$qualifier_term_id}) {
          warn "found cvterm by ID, but name doesn't match any cvterm: $qualifier_term_id " .
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
    my $evidence_code = delete $sub_qual_map->{evidence};

    my $evidence;

    if (defined $evidence_code) {
      $evidence = $self->objs()->{go_evidence_codes}->{$evidence_code};
    } else {
      warn "no evidence for: $embl_term_name in ", $pombe_feature->uniquename(), "\n";
      $evidence = "NO EVIDENCE";
    }

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
    $self->add_feature_cvtermprop($featurecvterm,
                                  evidence => $evidence);

    if (defined $sub_qual_map->{residue}) {
      $self->add_feature_cvtermprop($featurecvterm,
                                    residue => delete $sub_qual_map->{residue});
    }
  }

  $self->add_feature_cvtermprop($featurecvterm, qualifier => [@qualifiers]);

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

      if ($name eq 'qualifier') {
        my @bits = split /\|/, $value;
        $value = [@bits];
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

method process_ortholog($chado_object, $term, $sub_qual_map) {
  my $org_name;
  my $gene_bit;

  my $chado_object_type = $chado_object->type()->name();

  if ($chado_object_type ne 'gene' && $chado_object_type ne 'pseudogene') {
    return 1;
  }

  my $date = delete $sub_qual_map->{date};

  my $organism_common_name;

  if ($term =~ /^orthologous to S\. cerevisiae (.*)/) {
    $organism_common_name = 'Scerevisiae';
    $gene_bit = $1;
  } else {
    if ($term =~ /^human\s+(.*?)\s+ortholog$/) {
      $organism_common_name = 'human';
      $gene_bit = $1;
    } else {
      return 0;
    }
  }

  my $organism = $self->find_organism_by_common_name($organism_common_name);

  my @gene_names = ();

  for my $gene_name (split /\s+and\s+/, $gene_bit) {
    if ($gene_name =~ /^\S+$/) {
      push @gene_names, $gene_name;
    } else {
      die qq(gene name contains whitespace "$gene_name" from "$term");
    }
  }

  for my $ortholog_name (@gene_names) {
    warn "    creating ortholog from ", $chado_object->uniquename(),
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
      $self->add_feature_relationshipprop($rel, 'date', $date);
      my $db_xref = delete $sub_qual_map->{db_xref};
      my $pub = $self->get_pub_from_db_xref($term, $db_xref);
      $self->add_feature_relationship_pub($rel, $pub);
      $orth_guard->commit();
    } catch {
      die "  failed to create ortholog relation: $_\n";
    };
  }

  return 1;
}


method process_one_cc($chado_object, $bioperl_feature, $qualifier) {
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

  if (defined $cv_name) {
    $term =~ s/$cv_name, *//;

    if (exists $self->objs()->{cv_alt_names}->{$cv_name}) {
      map { $term =~ s/^$_, *//; } @{$self->objs()->{cv_alt_names}->{$cv_name}};
    }

    if (grep { $_ eq $cv_name } keys %{$self->objs()->{cv_alt_names}}) {
      my $chado_object_type = $chado_object->type()->name();

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
    try {
      if (!$self->process_ortholog($chado_object, $term, \%qual_map)) {
        warn "qualifier not recognised: $qualifier\n";
        return ();
      }
    } catch {
      warn $_;
      return ();
    }
  }

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
                          $product, { dbxref => 'PomBase:' . $product }, 1);
}

method check_unused_quals
{
  return unless $self->verbose();

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
