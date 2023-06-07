package PomBase::Chado::ExtensionProcessor;

=head1 NAME

PomBase::Chado::ExtensionProcessor - Code for processing annotation extensions

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::ExtensionProcessor

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

use Try::Tiny;
use Text::Trim qw(trim);

use Scalar::Util qw(looks_like_number);

use feature qw(state);

use Moose;

use PomBase::Chado;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::CvtermpropStorer';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::CvtermRelationshipStorer';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';

has verbose => (is => 'rw');
has cache => (is => 'ro', init_arg => undef, lazy_build => 1,
              builder => '_build_cache');
has pre_init_cache => (is => 'rw', default => 0);
has isa_cvterm => (is => 'ro', init_arg => undef, lazy_build => 1);

my $extension_cv_name = 'PomBase annotation extension terms';
my $extension_rel_status = 'extension_relations_status';

sub _build_cache {
  my $self = shift;

  if ($self->pre_init_cache()) {
    my $extension_cv =
      $self->chado()->resultset('Cv::Cv')->find({ name => $extension_cv_name });
    my $rs = $self->chado()->resultset('Cv::Cvterm');
    $rs = $rs->search(
      {
        cv_id => $extension_cv->cv_id(),
      });
    my %cache = ();
    my $extension_rel_status_term =
      $self->get_cvterm('cvterm_property_type', $extension_rel_status);
    while (defined (my $cvterm = $rs->next())) {
      if (grep {
        $_->type_id() == $extension_rel_status_term->cvterm_id() &&
        $_->value() eq 'created';
      } $cvterm->cvtermprops()) {
        $cache{$cvterm->name()} = 1;
      }
    }
    return \%cache;
  } else {
    return {};
  }
}

sub _build_isa_cvterm {
  my $self = shift;
  return $self->get_relation_cvterm('is_a');
}

sub _store_residue {
  my $self = shift;
  my $feature_cvterm = shift;
  my $residue = shift;

  $self->add_feature_cvtermprop($feature_cvterm, residue => $residue, 0);
}

sub store_extension {
  my $self = shift;
  my $feature_cvterm = shift;
  my $extensions = shift;

  my $old_cvterm = $feature_cvterm->cvterm();
  my $old_cv_name = $old_cvterm->cv()->name();

  my $new_name = $old_cvterm->name();

  my @rel_cv_names = @{$self->config()->{extension_relation_cv_names}};

  my $relation_transforms =
    $self->config()->{extension_relation_transform}->{$old_cv_name};

  map {
    if (defined $relation_transforms) {
      my $new_rel_name = $relation_transforms->{$_->{rel_name}};
      if (defined $new_rel_name) {
        $_->{rel_name} = $new_rel_name;
      }
    }
  } @$extensions;


  my %extensions_so_far = ();

  for my $extension (@$extensions) {
    my $rel_name = $extension->{rel_name};

    my $nested_extension = $extension->{nested_extension};

    my $this_extension =  '[' . $rel_name . '] ';

    if ($extension->{term}) {
      $this_extension .= $extension->{term}->name();
    } else {
      $this_extension .= $extension->{identifier};
    }

    if (defined $nested_extension) {
      $this_extension .= " ($nested_extension)";
    }

    $new_name .= " $this_extension";

    if (exists $extensions_so_far{$this_extension}) {
      my $termid = PomBase::Chado::id_of_cvterm($old_cvterm);
      if (!grep { $_ eq $termid } @{$self->config()->{allowed_duplicate_extensions}}) {
        die qq(duplicated extension: "$this_extension"\n);
      }
    } else {
      $extensions_so_far{$this_extension} = 1;
    }
  }

  my $new_term = $self->get_cvterm($extension_cv_name, $new_name);

  if (!defined $new_term) {
    $new_term = $self->find_or_create_cvterm($extension_cv_name, $new_name);

    $self->store_cvterm_rel($new_term, $old_cvterm, $self->isa_cvterm);
  }

  for my $extension (@$extensions) {
    my $rel_name = $extension->{rel_name};
    my $term = $extension->{term};

    my $extension_restriction_conf = $self->config()->{extension_restrictions};
    my $cv_restrictions_conf = $extension_restriction_conf->{$old_cv_name};

    if (defined $cv_restrictions_conf) {
      if (exists $cv_restrictions_conf->{allowed}) {
        if (!grep { $_ eq $rel_name } @{$cv_restrictions_conf->{allowed}}) {
          die "$rel_name() not allowed for $old_cv_name, annotation: ",
            $feature_cvterm->feature()->uniquename(), " <-> ",
            $old_cvterm->name() ,"\n";
        }
      }
      if (exists $cv_restrictions_conf->{not_allowed}) {
        if (grep { $_ eq $rel_name } @{$cv_restrictions_conf->{not_allowed}}) {
          die "$rel_name() not allowed for $old_cv_name, annotation: ",
            $feature_cvterm->feature()->uniquename(), " <-> ",
            $old_cvterm->name() ,"\n";
        }
      }
    } else {
      die "$rel_name() not allowed because no extension relations are configured for $old_cv_name\n";
    }

    my $all_not_allowed_rels = $extension_restriction_conf->{all}->{not_allowed};

    if (defined $all_not_allowed_rels) {
      if (grep { $_ eq $rel_name } @$all_not_allowed_rels) {
        die "$rel_name() not allowed in extension, annotation: ",
            $feature_cvterm->feature()->uniquename(), " <-> ",
            $old_cvterm->name() ,"\n";
      }
    }
  }

  if (!exists $self->cache()->{$new_name}) {
    # we load cvterms from older builds from an OBO file but the file
    # doesn't store the non-isa relations and the props - recreate them
    $self->cache()->{$new_name} = 1;

    $self->store_cvtermprop($new_term, $extension_rel_status, 'created');

    for my $extension (@$extensions) {
      my $rel_name = $extension->{rel_name};
      my $term = $extension->{term};
      my $nested_extension = $extension->{nested_extension};

      my $rel = undef;

      for my $rel_cv_name (@rel_cv_names) {
        warn "checking for $rel_name in $rel_cv_name\n" if $self->verbose;
        $rel = $self->find_cvterm_by_name($rel_cv_name, $rel_name,
                                          query_synonyms => 0);
        last if defined $rel;
      }

      if (!defined $rel) {
        for my $rel_cv_name (@rel_cv_names) {
          warn "checking for $rel_name using cvtermsynonyms in $rel_cv_name\n" if $self->verbose;
          $rel = $self->find_cvterm_by_name($rel_cv_name, $rel_name,
                                            query_synonyms => 1);
          last if defined $rel;
        }
      }

      if (!defined $rel) {
        for my $rel_cv_name (@rel_cv_names) {
          warn "checking for obsolete $rel_name in $rel_cv_name\n" if $self->verbose;
          $rel = $self->find_cvterm_by_name($rel_cv_name, $rel_name,
                                            include_obsolete => 1);
          if (defined $rel) {
            die "found relation term $rel_name in $rel_cv_name but it's obsolete\n";
          }
        }

        die "can't find relation cvterm for: $rel_name in these CVs: @rel_cv_names\n";
      }

      if (defined $term) {
        if ($self->get_cvterm_rel($new_term, $term, $rel)->count() > 0) {
          my $id = PomBase::Chado::id_of_cvterm($term);
          my $feature_uniquename = $feature_cvterm->feature()->uniquename();
          warn "in $feature_uniquename, duplicated annotation extension for ",
            $rel->name(), " (", $id, ")\n";
        } else {
          warn qq'storing new cvterm_relationship of type "' . $rel->name() .
            " subject: " . $new_term->name() .
            " object: " . $term->name() . "\n" if $self->verbose();
          my $term_rel = $self->store_cvterm_rel($new_term, $term, $rel);

          if (defined $nested_extension) {
            $self->store_cvtermprop($new_term, 'nested_extension', $nested_extension);
          }
        }
      } else {
        my $identifier = $extension->{identifier};
        if ($rel_name eq 'localization_target_is') {
          $rel_name = 'localization_target';
        }

        my $ex_type = 'annotation_extension_relation-' . $rel->name();

        warn qq{storing extension as cvtermprop for $new_name: $ex_type -> $identifier\n} if $self->verbose();

        state $ranks = {};

        my $key = $new_term->cvterm_id() . ":$ex_type:$identifier";

        # to avoid duplicate cvtermprop errors:
        if (exists $ranks->{$key}) {
          $ranks->{$key}++;
        } else {
          $ranks->{$key} = 0;
        }

        $self->store_cvtermprop($new_term, $ex_type, $identifier, $ranks->{$key});
      }
    }
  }

  # make sure we don't create a duplicate annotation
  my $existing_fc_rs =
    $self->chado()->resultset('Sequence::FeatureCvterm')
      ->search({ cvterm_id => $new_term->cvterm_id(),
                 feature_id => $feature_cvterm->feature_id(),
                 pub_id => $feature_cvterm->pub_id() });

  my $update_failed = undef;

  my $new_rank = 0;

  if ($existing_fc_rs->count() > 0) {

    my $max_rank = 0;

    while (defined (my $fc = $existing_fc_rs->next())) {
      if ($fc->rank() > $max_rank) {
        $max_rank = $fc->rank();
      }
    }

    $new_rank = $max_rank + 1;

    my @props_to_check = qw(evidence residue condition qualifier gene_product_form_id with from quant_gene_ex_copies_per_cell quant_gene_ex_avg_copies_per_cell);

    my @prop_names_for_query =
      map {
        ('type.name' => $_);
      } @props_to_check;

    my $current_props_rs = $feature_cvterm->feature_cvtermprops()
      ->search({ -or => \@prop_names_for_query },
               { join => 'type' });

    my $display_undef = 'not set';

    my %current_props = ();

    while (defined (my $prop = $current_props_rs->next())) {
      push @{$current_props{$prop->type()->name()}}, $prop->value();
    }

    my $_make_prop_string = sub {
      my $props_map = shift;
      return
        join ", ",
        map {
          $_ . ': "' . (join ',', sort @{$props_map->{$_}}) . '"';
        } sort keys %{$props_map};
    };

    my $current_props_string = $_make_prop_string->(\%current_props);

    for my $fc ($existing_fc_rs->all()) {
      my $fc_props_rs = $fc->feature_cvtermprops()
        ->search({ -or => [@prop_names_for_query, 'type.name' => 'canto_session'] },
                 { join => 'type' });

      my %fc_props = ();

      my $fc_session = 'UNKNOWN';

      while (defined (my $fc_prop = $fc_props_rs->next())) {
        if ($fc_prop->type()->name() eq 'canto_session') {
          $fc_session = $fc_prop->value();
        } else {
          push @{$fc_props{$fc_prop->type()->name()}}, $fc_prop->value();
        }
      }

      my $fc_props_string = $_make_prop_string->(\%fc_props);

      if ($current_props_string eq $fc_props_string) {
        $update_failed = qq|that annotation has already been stored in Chado with properties:  $current_props_string  from session: $fc_session|;
        last;
      }
    }
  }

  if (!defined $update_failed) {
    $feature_cvterm->cvterm($new_term);
    $feature_cvterm->rank($new_rank);

    try {
      $feature_cvterm->update();
    } catch {
      $update_failed = $_;
    };
  }

  if ($self->verbose() || defined $update_failed) {
    my $feature = $feature_cvterm->feature();
    my $feature_description =
        $feature_cvterm->feature()->uniquename();

    if ($feature->type()->name eq 'genotype') {
      my @allele_names = ();

      for my $rel ($feature->feature_relationship_objects()) {
        my $allele_name = $rel->subject()->name();

        if ($allele_name) {
          push @allele_names, $allele_name;
        }
      }

      if (@allele_names) {
        $feature_description .= ' (' . join(" ", @allele_names) . ')';
      }
    }

    my $warn_message =
      'storing feature_cvterm from ' . $feature_description . ' to ' .
      $new_term->name();

    if (defined $update_failed) {
      die $warn_message . " - failed to store feature_cvterm: $update_failed\n";
    } else {
      warn "$warn_message\n" ;
    }
  }

  return $new_term;
}

sub check_targets {
  my $self = shift;
  my $target_is_quals = shift;
  my $target_of_quals = shift;

  my $organism = $self->find_organism_by_common_name('pombe');

  die unless defined $organism;

  while (my ($target_uniquename, $details) = each(%{$target_of_quals})) {
    for my $detail (@$details) {
      my $gene_name = $detail->{name};

      my $gene1_feature = undef;
      try {
        $gene1_feature = $self->find_chado_feature($gene_name, 1, 1, $organism);
      } catch {
        warn "problem with target annotation of ", $detail->{feature}->uniquename(), ": $_";
      };
      if (!defined $gene1_feature) {
        next;
      }

      my $gene1_uniquename = $gene1_feature->uniquename();

      if (!exists $target_is_quals->{$gene1_uniquename} ||
          !grep {
            my $current = $_;
            my $target_feature;
            try {
              $target_feature = $self->find_chado_feature($current->{name}, 1, 1, $organism);
            } catch {
              warn "problem on gene ", $current->{feature}->uniquename(), ": $_";
            };

            if (defined $target_feature) {
              $target_feature->uniquename() eq $target_uniquename;
            } else {
              0;
            }
          } @{$target_is_quals->{$gene1_uniquename}}) {

        my $name_bit;

        my $target_feature;
        try {
          $target_feature = $self->find_chado_feature($target_uniquename, 1, 1, $organism);
        } catch {
        };

        if (defined $target_feature && defined $target_feature->name()) {
          $name_bit = $target_feature->name();
        } else {
          $name_bit = $target_uniquename;
        }
        warn qq:no "target is $name_bit" in $gene_name ($gene1_uniquename)\n:;
      }
    }
  }
}

sub process {
  my $self = shift;
  my $post_process_data = shift;
  my $target_is_quals = shift;
  my $target_of_quals = shift;

  $self->check_targets($target_is_quals, $target_of_quals);

  while (my ($feature_cvterm_id, $data_list) = each %{$post_process_data}) {
    for my $data (@$data_list) {
      my $feature_cvterm = $data->{feature_cvterm};
      my $qualifiers = $data->{qualifiers};

      try {
        $self->process_one_annotation($feature_cvterm, $qualifiers->{annotation_extension});
      } catch {
        warn "failed to add annotation extension to ",
          $feature_cvterm->feature()->uniquename(), ' <-> ',
          $feature_cvterm->cvterm()->name(), ": $_";
      }
    }
  }

}

my $comma_substitute = "<<COMMA>>";

sub _replace_commas
{
  my $string = shift;

  $string =~ s/,/$comma_substitute/g;
  return $string;
}

sub _unreplace_commas
{
  my $string = shift;

  $string =~ s/$comma_substitute/,/g;
  return $string;
}

sub _process_identifier {
  my $self = shift;
  my $feature_uniquename = shift;
  my $rel_name = shift;
  my $arg = shift;

  my $identifier = trim($arg);

  my $nested_extension_bit = undef;
  if ($identifier =~ /(.+?)(\^.*)/) {
    # nested annotation extension - store and ignore
    $identifier = $1;
    $nested_extension_bit = $2;
  }

  my $term_id = undef;
  my $term = undef;
  if ($identifier =~ /^(\w+):(\d+)$/) {
    $term_id = $identifier;
    $term = $self->find_cvterm_by_term_id($term_id);
    if (!defined $term) {
      die "can't find term with ID: $term_id\n";
    }
  } else {
    if ($identifier =~ /^(PomBase|GeneDB_?Spombe):([\w\d\.\-]+)$/i) {
      $identifier = $2;
      my $organism = $self->find_organism_by_common_name('pombe');
      try {
        my $ref_feature =
          $self->find_chado_feature($identifier, 1, 1, $organism,
                                    ['gene', 'pseudogene', 'promoter']);
        $identifier = 'PomBase:' . $ref_feature->uniquename();
      } catch {
        chomp (my $message = $_);
        warn "in extension for $feature_uniquename, can't find " .
          "feature with identifier: $identifier - $message\n";
      };
    } else {
      if ($identifier =~ /^(UniProtKB:.*|SGD:S\d+|Pfam:PF\d+)$/) {
        $identifier = $1;
      } else {
        if (($rel_name eq 'has_penetrance' || $rel_name eq 'occupancy') &&
            ($identifier =~ /^[><]?~?(.*?)\%?$/ && looks_like_number($1) ||
             $identifier =~ /^~?\d+(?:\.\d+)?\%?-~?\d+(?:\.\d+)?\%?$/)) {
          # the "identifier" is the percentage value
          $identifier =~ s/(\d+)\%/$1/g;
        } else {
          if ($rel_name eq 'multiplicity') {
            if ($identifier !~ /^\d+$/) {
              die "multiplicity relation value must be a number, not: $identifier\n";
            }
          } else {
          my $organism = $self->find_organism_by_taxonid($self->config()->{taxonid});
          my $ref_feature = undef;
          try {
            # try gene name/uniquename with no prefix
            $ref_feature =
              $self->find_chado_feature($identifier, 1, 1, $organism,
                                        ['gene', 'pseudogene']);
          };

          try {
            # maybe it's a transcript?  eg. "SPAC17G6.02c.2"
            $ref_feature =
              $self->find_chado_feature($identifier, 0, 0, $organism, ['mRNA']);
          };

          if ($ref_feature) {
            $identifier =
              $self->config()->{database_name} . ':' . $ref_feature->uniquename();
          } else {
            die "in annotation extension for $feature_uniquename, can't " .
              qq|parse identifier in "$rel_name($identifier)"\n|;
          };
          }
        }
      }
    }
  }

  return {
    rel_name => $rel_name,
      term => $term,
      term_id => $term_id,
      identifier => $identifier,
      nested_extension => $nested_extension_bit,
    };
}

sub process_one_annotation {
  my $self = shift;
  my $featurecvterm = shift;
  my $extension_text = shift;
  my $extensions = shift;

  my $feature_uniquename = $featurecvterm->feature()->uniquename();

  warn "processing annotation extension for $feature_uniquename <-> ",
    $featurecvterm->cvterm()->name(), "   ext: $extension_text\n" if $self->verbose();

  (my $extension_copy = $extension_text) =~ s/(\([^\)]+\))/_replace_commas($1)/eg;

  my @extension_qualifiers = sort split /(?<=\))\||,/, $extension_copy;

  my @extensions = map {
    my $bit = _unreplace_commas($_);
    if ($bit =~ /^\s*(\w+)\((.+)\)\s*$/) {
      my $rel_name = $1;
      my $detail = $2;

      if ($rel_name eq 'residue') {
        $self->_store_residue($featurecvterm, $detail);
        ();
      } else {
        map {
          $self->_process_identifier($feature_uniquename, $rel_name, $_);
        } split /\|/, $detail;
      }
    } else {
      die "annotation extension qualifier on $feature_uniquename not understood: $_\n";
    }
  } @extension_qualifiers;

  push @extensions,
    map {
      my $rel_name = $_->{relation};
      my $value = $_->{rangeValue};

      $self->_process_identifier($feature_uniquename, $rel_name, $value);
    } @$extensions;

  if (@extensions) {
    $self->store_extension($featurecvterm, \@extensions);
  }
}

1;
