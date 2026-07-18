package PomBase::Chado::ReciprocalModifications;

=head1 NAME

PomBase::Chado::ReciprocalModifications - Warn about missing reciprocal
  annotations for modifications

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::ReciprocalModifications

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ExtensionDisplayer';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has mod_to_mf_mapping => (is => 'rw', init_arg => undef);
has mf_to_mod_mapping => (is => 'rw', init_arg => undef);
has missing_activities_file => (is => 'rw', init_arg => undef);
has missing_modifications_file => (is => 'rw', init_arg => undef);
has child_map => (is => 'rw', init_arg => undef);

sub BUILD {
  my $self = shift;

  my $mapping_file = undef;
  my $missing_activities_file = undef;
  my $missing_modifications_file = undef;

  my @opt_config = ('mapping-file=s' => \$mapping_file,
                    'missing-activites-file=s' => \$missing_activities_file,
                    'missing-modifications-file=s' => \$missing_modifications_file);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!$mapping_file) {
    die "missing argument: --mapping-file\n";
  }

  if (!$missing_activities_file) {
    die "missing argument: --missing-activites-file\n";
  }

  if (!$missing_modifications_file) {
    die "missing argument: --missing-modifications-file\n";
  }

  open my $mapping_file_fh, '<', $mapping_file
    or die "can't open $mapping_file: $!\n";

  my $header = <$mapping_file_fh>;

  my %mod_to_mf_mapping = ();
  my %mf_to_mod_mapping = ();

  while (defined (my $line = <$mapping_file_fh>)) {
    chomp $line;

    my ($mod_id, $mod_name, $extension_name, $mf_name,
        $mf_id) = split "\t", $line;

    if (!$mod_name || !$mf_name || $mod_name eq '?' || $mf_name eq '?') {
      next;
    }

    my %mapping_conf = (
      mod_name => $mod_name,
      mod_id => $mod_id,
      extension_name => $extension_name,
      mf_name => $mf_name,
      mf_id => $mf_id,
    );

    push @{$mf_to_mod_mapping{$mf_name}}, \%mapping_conf;
    push @{$mod_to_mf_mapping{$mod_name}}, \%mapping_conf;
  }

  $self->mf_to_mod_mapping(\%mf_to_mod_mapping);
  $self->mod_to_mf_mapping(\%mod_to_mf_mapping);

  $self->missing_activities_file($missing_activities_file);
  $self->missing_modifications_file($missing_modifications_file);

  $self->child_map($self->make_child_map());
}

sub make_child_map {
  my $self = shift;

  my $chado_dbh = $self->chado()->storage()->dbh();

  my $query = <<'EOQ';
SELECT s_db.name || ':' || s_x.accession subject_term_id,
       pt.name AS relation,
       o_db.name || ':' || o_x.accession object_term_id
FROM cvtermpath p
JOIN cvterm s ON s.cvterm_id = p.subject_id
JOIN dbxref s_x ON s_x.dbxref_id = s.dbxref_id
JOIN db s_db ON s_db.db_id = s_x.db_id
JOIN cvterm o ON o.cvterm_id = p.object_id
JOIN dbxref o_x ON o_x.dbxref_id = o.dbxref_id
JOIN db o_db ON o_db.db_id = o_x.db_id
JOIN cv s_cv ON s.cv_id = s_cv.cv_id
JOIN cvterm pt ON p.type_id = pt.cvterm_id
WHERE s_cv.name in ('molecular_function', 'PSI-MOD')
  AND pathdistance > 0
  AND pt.name = 'is_a';
EOQ

  my $sth = $chado_dbh->prepare($query);
  $sth->execute();

  my %child_map = ();

  while (my ($subject_term_id, $relation_name, $object_term_id) =
         $sth->fetchrow_array()) {
    push @{$child_map{$object_term_id}}, $subject_term_id;
  }

  return \%child_map;
}

sub get_props {
  my $self = shift;
  my $fc = shift;

  my $evidence_code = '';
  my $eco_evidence = '';
  my $date = '';

  my $rs = $fc->feature_cvtermprops()
    ->search({ -or => [ 'type.name' => 'evidence', 'type.name' => 'eco_evidence', 'type.name' => 'date' ] },
             { join => 'type' });

  while (defined (my $prop = $rs->next())) {
    if ($prop->type()->name() eq 'evidence') {
      $evidence_code = $prop->value();

      if ($evidence_code eq 'tryptic phosphopeptide mapping assay evidence used in automatic assertion' ||
          $evidence_code eq 'experimental evidence') {
        $evidence_code = 'Inferred from Experiment';
      }
    } else {
      if ($prop->type()->name() eq 'eco_evidence') {
        $eco_evidence = $prop->value();
      } else {
        $date = $prop->value();
      }
    }
  }

  return ($evidence_code, $eco_evidence, $date);
}

sub check_activity {
  my $self = shift;
  my $act_parent_term_name = shift =~ s/'/''/gr;
  my $mod_parent_term_name = shift =~ s/'/''/gr;
  my $missing_activities = shift;
  my $missing_modifications = shift;
  my $conf = shift;

  my $chado = $self->chado();
  my $dbh = $chado->storage()->dbh();

  my $db_name = $self->config()->{database_name};

  my $conf_ext_name = $conf->{extension_name};

  my $missing_mod = 0;
  my $missing_act = 0;

  my $sql = <<"EOQ";
SELECT feature_cvterm_id
FROM pombase_feature_cvterm_ext_resolved_terms fc
WHERE cvterm_name like '%[has_input%'
  AND base_cvterm_id IN
    (SELECT subject_id FROM cvtermpath WHERE object_id IN
         (SELECT cvterm_id FROM cvterm
          WHERE (name = '$act_parent_term_name'))
       AND type_id IN (SELECT cvterm_id FROM cvterm WHERE name = 'is_a')
       AND pathdistance >= 0)

-- AND fc.pub_id IN (SELECT pub_id FROM pub WHERE uniquename = 'PMID:36650056')

ORDER BY cvterm_name
EOQ

  my $feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm')
    ->search({ feature_cvterm_id => { -in => \$sql },
             },
             { join => { cvterm => 'cv' },
               prefetch => ['feature', 'pub'],
             });

  my %activity_genes_and_targets = ();

#  warn "$act_parent_term_name <-> $mod_parent_term_name\n";
#
#  warn "starting activity query\n";
#  warn "  count: ", $feature_cvterm_rs->count(), "\n";

  while (defined (my $fc = $feature_cvterm_rs->next())) {
    my ($ext_parts, $parent_cvterm) = $self->get_ext_parts($fc);

    my $feature_uniquename =
      $fc->feature()->uniquename() =~ s/\.\d$//r;
    my $pub_uniquename = $fc->pub()->uniquename();

    for my $ext_part (@$ext_parts) {
      if ($ext_part->{rel_type_name} eq 'has_input') {
        my $target = $ext_part->{detail} =~ s/^$db_name://r;
        my $key = "$pub_uniquename-$feature_uniquename-$target";
        push @{$activity_genes_and_targets{$key}}, $fc;
      }
    }
  }

  $sql = <<"EOQ";
SELECT feature_cvterm_id
FROM pombase_feature_cvterm_ext_resolved_terms fc
WHERE cvterm_name like '%[$conf_ext_name%'
  AND base_cvterm_id IN
    (SELECT subject_id FROM cvtermpath WHERE object_id IN
         (SELECT cvterm_id FROM cvterm
          WHERE (name = '$mod_parent_term_name'))
       AND type_id IN (SELECT cvterm_id FROM cvterm WHERE name = 'is_a')
       AND pathdistance >= 0)

-- AND fc.pub_id IN (SELECT pub_id FROM pub WHERE uniquename = 'PMID:36650056')

ORDER BY cvterm_name
EOQ

  $feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm')
    ->search({ feature_cvterm_id => { -in => \$sql },
             },
             { join => { cvterm => 'cv' },
               prefetch => ['feature', 'pub'],
             });

  my %mod_genes_and_ext = ();

# warn "$act_parent_term_name <-> $mod_parent_term_name\n";
# warn "starting modification query\n";
# warn "  count: ", $feature_cvterm_rs->count(), "\n";

  while (defined (my $fc = $feature_cvterm_rs->next())) {
    my ($ext_parts, $parent_cvterm) = $self->get_ext_parts($fc);

    my $feature_uniquename =
      $fc->feature()->uniquename() =~ s/\.\d$//r;
    my $pub_uniquename = $fc->pub()->uniquename();

    for my $ext_part (@$ext_parts) {
      if ($ext_part->{rel_type_name} eq $conf_ext_name) {
        my $ext_name = $ext_part->{detail} =~ s/^$db_name://r;
        my $key = "$pub_uniquename-$feature_uniquename-$ext_name-" .
          $ext_part->{rel_type_name};

        push @{$mod_genes_and_ext{$key}}, $fc;
      }
    }
  }

  for my $key (keys %activity_genes_and_targets) {
    my ($pub, $activity_gene, $target) = split /-/, $key;

    my $ext_name = $conf->{extension_name};
    my $mod_key = "$pub-$target-$activity_gene-$ext_name";

    if (defined $mod_genes_and_ext{$mod_key}) {
#      print "found modification: $pub $target $ext_name($activity_gene)\n";
    } else {
      $missing_mod++;
      print "missing modification: $pub $target $ext_name($activity_gene)\n";

      my $mod_id = $conf->{mod_id};
      my @fcs = @{$activity_genes_and_targets{$key}};
      my $inferred_ext = "$ext_name(PomBase:$activity_gene)";

      for my $fc (@fcs) {
        my ($evidence_code, $eco_evidence, $date) = $self->get_props($fc);

        push @{$missing_modifications}, {
          gene => $target,
          term_id => $mod_id,
          pub => $pub,
          evidence_code => $eco_evidence,
          date => $date,
          extension => $inferred_ext
        };
      }
    }
  }

  for my $key (keys %mod_genes_and_ext) {
    my ($pub, $mod_gene, $gene_in_ext, $ext_rel) = split /-/, $key;

    my $act_key = "$pub-$gene_in_ext-$mod_gene";

    if (defined $activity_genes_and_targets{$act_key}) {
#      print "found activity: $pub $ext_name modifies($mod_gene)\n";
    } else {
      $missing_act++;
      print "missing activity: $pub $gene_in_ext $ext_rel($mod_gene)\n";

      my $mf_id = $conf->{mf_id};
      my @fcs = @{$mod_genes_and_ext{$key}};
      my $inferred_ext = "has_input(PomBase:$mod_gene)";

      for my $fc (@fcs) {
        my ($evidence_code, $eco_evidence, $date) = $self->get_props($fc);

        push @{$missing_activities}, {
          gene => $gene_in_ext,
          term_id => $mf_id,
          pub => $pub,
          evidence_code => $evidence_code,
          date => $date,
          extension => $inferred_ext
        };
      }
    }
  }

  return ($missing_act, $missing_mod);
}

sub is_redundant {
  my $self = shift;
  my $test_annotation = shift;
  my $other_annotations = shift;

  my $child_terms = $self->child_map()->{$test_annotation->{term_id}};

  if (!defined $child_terms) {
    # no child term
    return 0;
  }

  my @child_terms = @$child_terms;

  for my $child_term (@child_terms) {
    if ($child_term eq $test_annotation->{term_id}) {
      next;
    }
    for my $other_annotation (@$other_annotations) {
      if ($other_annotation->{term_id} eq $child_term) {
        return 1;
      }
    }
  }

  return 0;
}

sub print_missing {
  my $self = shift;
  my $missing_fh = shift;
  my $missing = shift;
  my $printer = shift;

  my @missing = @$missing;

  my %seen_missing = ();

  for my $missing_annotation (@missing) {
    my $gene = $missing_annotation->{gene};
    my $term_id = $missing_annotation->{term_id};
    my $pub = $missing_annotation->{pub};
    my $evidence_code = $missing_annotation->{evidence_code};
    my $extension = $missing_annotation->{extension};
    my $date = $missing_annotation->{date};

    my $key = join "-=-", $gene, $term_id, $pub, $evidence_code, $extension;

    if ($seen_missing{$key} &&
        $date gt $seen_missing{$key}->{date} ||
        !$seen_missing{$key})
      {
        $seen_missing{$key} = $missing_annotation;
      }
  }

  my %grouped_mf = ();

  for my $missing_annotation (values %seen_missing) {
    my $gene = $missing_annotation->{gene};
    my $pub = $missing_annotation->{pub};
    my $evidence_code = $missing_annotation->{evidence_code};
    my $extension = $missing_annotation->{extension};
    my $date = $missing_annotation->{date};

    my $group_key = join "-=-", $gene, $pub, $evidence_code, $extension;

    push @{$grouped_mf{$group_key}}, $missing_annotation;
  }

  for my $grouped_mf_group (values %grouped_mf) {
    my @grouped_mf_group = @$grouped_mf_group;

    for my $missing_annotation (@grouped_mf_group) {
      if ($self->is_redundant($missing_annotation, \@grouped_mf_group)) {
        next;
      }

      $printer->($missing_fh, $missing_annotation);
    }
  }
}

sub process {
  my $self = shift;

  my @missing_activities = ();
  my @missing_modifications = ();

  for my $activity_parent_term_name (sort keys %{$self->mf_to_mod_mapping()}) {
    for my $conf (@{$self->mf_to_mod_mapping()->{$activity_parent_term_name}}) {
      my $mod_parent_term_name = $conf->{mod_name};

      my $ext_name = $conf->{extension_name};

      print qq|checking "$activity_parent_term_name" [$ext_name] "$mod_parent_term_name"\n|;

      my ($missing_act, $missing_mod) =
        $self->check_activity($activity_parent_term_name, $mod_parent_term_name,
                              \@missing_activities, \@missing_modifications, $conf);

      if ($missing_act == 0 && $missing_mod == 0) {
        print "no missing activities or modifications\n";
      }

      print "\n";
    }
  }

  my $missing_activities_file = $self->missing_activities_file();
  open my $missing_activities_fh, '>', $missing_activities_file or
    die "can't open $missing_activities_file for writing\n";

  my $mf_printer = sub {
    my $fh = shift;
    my $missing_annotation = shift;

    my $gene = $missing_annotation->{gene};
    my $term_id = $missing_annotation->{term_id};
    my $pub = $missing_annotation->{pub};
    my $evidence_code = $missing_annotation->{evidence_code};
    my $extension = $missing_annotation->{extension};
    my $date = $missing_annotation->{date};

    print $fh "PomBase\t$gene\t\t\t$term_id\t$pub\t$evidence_code\t\tX\t\t\tprotein\ttaxon:4896\t$date\tPomBase\t$extension\t\n";
  };

  $self->print_missing($missing_activities_fh, \@missing_activities,
                       $mf_printer);

  close $missing_activities_fh or die;

  my $missing_modifications_file = $self->missing_modifications_file();
  open my $missing_modifications_fh, '>', $missing_modifications_file or
    die "can't open $missing_modifications_file for writing\n";

  my $mod_printer = sub {
    my $fh = shift;
    my $missing_annotation = shift;

    my $gene = $missing_annotation->{gene};
    my $term_id = $missing_annotation->{term_id};
    my $pub = $missing_annotation->{pub};
    my $evidence_code = $missing_annotation->{evidence_code};
    my $extension = $missing_annotation->{extension};
    my $date = $missing_annotation->{date};

    if ($date =~ /^(\d\d\d\d)(\d\d)(\d\d)$/) {
      $date = "$1-$2-$3";
    }

    print $fh "$gene\t\t$term_id\t$evidence_code\t\t$extension\t$pub\t4896\t$date\n";
  };

  $self->print_missing($missing_modifications_fh, \@missing_modifications,
                       $mod_printer);

  close $missing_modifications_fh;
}

1;
