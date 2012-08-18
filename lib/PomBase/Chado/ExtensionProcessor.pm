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

use perl5i::2;
use Moose;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::CvtermpropStorer';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::ChadoObj';
with 'PomBase::Role::CvtermRelationshipStorer';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';

has verbose => (is => 'ro');
has cache => (is => 'ro', init_arg => undef, lazy_build => 1,
              builder => '_build_cache');
has pre_init_cache => (is => 'rw', default => 0);

my $extension_cv_name = 'PomBase annotation extension terms';

method _build_cache
{
  if ($self->pre_init_cache()) {
    my $extension_cv =
      $self->chado()->resultset('Cv::Cv')->find({ name => $extension_cv_name });
    my $rs = $self->chado()->resultset('Cv::Cvterm')->search({ cv_id => $extension_cv->cv_id() });
    my %cache = ();
    while (defined (my $cvterm = $rs->next())) {
      $cache{$cvterm->name()} = 1;
    }
    return \%cache;
  } else {
    return {};
  }
}

method store_extension($feature_cvterm, $extensions)
{
  my $old_cvterm = $feature_cvterm->cvterm();

  my $new_name = $old_cvterm->name();

  my $go_relationship_cv_name = 'go/extensions/gorel';
  my $phenotype_relationship_cv_name = 'fypo_extension_relations';
  my $psi_mod_relationship_cv_name = 'PSI-MOD_extension_relations';

  for my $extension (@$extensions) {
    my $rel_name = $extension->{rel_name};

    my $nested_extension = $extension->{nested_extension};

    $new_name .=  ' [' . $rel_name . '] ';

    if ($extension->{term}) {
      $new_name .= $extension->{term}->name();
    } else {
      $new_name .= $extension->{identifier};
    }

    if (defined $nested_extension) {
      $new_name .= " ($nested_extension)";
    }
  }

  my $new_term = $self->get_cvterm($extension_cv_name, $new_name);

  if (!defined $new_term) {
    $new_term = $self->find_or_create_cvterm($extension_cv_name, $new_name);

    my $isa_cvterm = $self->get_cvterm('relationship', 'is_a');
    $self->store_cvterm_rel($new_term, $old_cvterm, $isa_cvterm);
  }

  if (!exists $self->cache()->{$new_name}) {
    # we load cvterms from older builds from an OBO file but the file
    # doesn't store the non-isa relations and the props - recreate them
    $self->cache()->{$new_name} = 1;

    for my $extension (@$extensions) {
      my $rel_name = $extension->{rel_name};
      my $term = $extension->{term};
      my $nested_extension = $extension->{nested_extension};

      if (defined $term) {
        my $rel = $self->find_cvterm_by_name($go_relationship_cv_name, $rel_name);
        if (!defined $rel) {
          $rel = $self->find_cvterm_by_name($phenotype_relationship_cv_name, $rel_name);
        }
        if (!defined $rel) {
          $rel = $self->find_cvterm_by_name($psi_mod_relationship_cv_name, $rel_name);
        }
        my $old_cv_name = $old_cvterm->cv()->name();
        my $extension_restriction_conf = $self->config()->{extension_restrictions};
        my $cv_restrictions_conf = $extension_restriction_conf->{$old_cv_name};

        if (defined $cv_restrictions_conf) {
          if (exists $cv_restrictions_conf->{allowed}) {
            if (!grep { $_ eq $rel_name } @{$cv_restrictions_conf->{allowed}}) {
              die "$rel_name() not allowed for $old_cv_name\n";
            }
          }
          if (exists $cv_restrictions_conf->{not_allowed}) {
            if (grep { $_ eq $rel_name } @{$cv_restrictions_conf->{not_allowed}}) {
              die "$rel_name() not allowed for $old_cv_name\n";
            }
          }
        }

        my $all_not_allowed_rels = $extension_restriction_conf->{all}->{not_allowed};

        if (defined $all_not_allowed_rels) {
          if (grep { $_ eq $rel_name } @$all_not_allowed_rels) {
            die "$rel_name() not allowed in extension\n";
          }
        }

        if (!defined $rel) {
          die "can't find relation cvterm for: $rel_name\n";
        }

        if ($self->get_cvterm_rel($new_term, $term, $rel)->count() > 0) {
          my $id = PomCur::Chado::id_of_cvterm($term);
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

        my $ex_type = 'annotation_extension_relation-' . $rel_name;

        warn qq{storing extension as cvtermprop: $ex_type -> $identifier\n} if $self->verbose();

        $self->store_cvtermprop($new_term, $ex_type, $identifier);
      }
    }
  }

  warn 'storing feature_cvterm from ' .
    $feature_cvterm->feature()->uniquename() . ' to ' .
    $new_term->name() . "\n" if $self->verbose();
  $feature_cvterm->cvterm($new_term);

  $feature_cvterm->update();

  return $new_term;
}

method check_targets($target_is_quals, $target_of_quals)
{
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

method process($post_process_data, $target_is_quals, $target_of_quals)
{
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

method process_one_annotation($featurecvterm, $extension_text)
{
  my $feature_uniquename = $featurecvterm->feature()->uniquename();

  warn "processing annotation extension for $feature_uniquename <-> ",
    $featurecvterm->cvterm()->name(), "\n" if $self->verbose();

  (my $extension_copy = $extension_text) =~ s/(\([^\)]+\))/_replace_commas($1)/eg;

  my @extension_qualifiers = sort split /(?<=\))\||,/, $extension_copy;

  my @extensions = map {
    my $bit = _unreplace_commas($_);
    if ($bit =~ /^\s*(\w+)\((.+)\)\s*$/) {
      my $rel_name = $1;
      my $detail = $2;

      map {
        my $identifier = $_;

        my $nested_extension_bit = undef;
        if ($identifier =~ /(.+?)(\^.*)/) {
          # nested annotation extension - store and ignore
          $identifier = $1;
          $nested_extension_bit = $2;
        }

        my $term_id = undef;
        my $term = undef;
        if ($identifier =~ /^\w+:\d+$/) {
          $term_id = $identifier;
          $term = $self->find_cvterm_by_term_id($term_id);
          if (!defined $term) {
            die "can't find term with ID: $term_id\n";
          }
        } else {
          if ($identifier =~ /^(PomBase|GeneDB_?Spombe):([\w\d\.\-]+)/i) {
            $identifier = $2;
          } else {
            if ($identifier =~ /^(Pfam:PF\d+)$/) {
              $identifier = $1;
            } else {
              warn "in annotation extension for $feature_uniquename, can't parse identifier: $identifier\n";
              ();
            }
          }
        }

        {
          rel_name => $rel_name,
          term => $term,
          term_id => $term_id,
          identifier => $identifier,
          nested_extension => $nested_extension_bit,
        }
      } split /\|/, $detail;
    } else {
      die "annotation extension qualifier on $feature_uniquename not understood: $_\n";
      ();
    }
  } @extension_qualifiers;

  if (@extensions) {
    $self->store_extension($featurecvterm, \@extensions);
  }
}

1;
