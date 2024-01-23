package PomBase::Role::PhenotypeFeatureFinder;

=head1 NAME

PomBase::Role::PhenotypeFeatureFinder - Legacy code for finding and
                                        creating alleles

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::PhenotypeFeatureFinder

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use feature qw(state);

use PomBase::Chado::FixAlleleNames;

use Moose::Role;

use utf8::all;

requires 'allele_type_from_desc';
requires 'get_cvterm';
requires 'find_chado_feature';
requires 'find_organism_by_full_name';
requires 'store_feature_rel';
requires 'config';
requires 'store_feature_relationshipprop';
requires 'genotype_cache';

has allele_types => (is => 'rw', init_arg => undef, lazy_build => 1);

sub _build_allele_types {
  my $self = shift;
  my %allele_types = ();

  my $allele_types_rs =
    $self->chado()->resultset('Cv::Cvterm')
         ->search({ 'cv.name' => 'PomBase allele types' },
                  { join => 'cv' });

  while (defined (my $allele_type_cvterm = $allele_types_rs->next())) {
    $allele_types{$allele_type_cvterm->name()} = 1;
  }

  return { %allele_types };
}


=head2 get_gene

 Usage   : my $gene = $self->get_gene($gene_data);
 Function: Helper method for get_allele() to find genes
 Args    : $gene_data - a hash ref with keys:
                uniquename - the gene uniquename
                organism   - the full organism name like "Genus species"

=cut
sub get_gene {
  my $self = shift;
  my $gene_data = shift;

  if (!defined $gene_data) {
    croak 'no $gene_data passed to get_gene()';
  }

  state $cache = {};

  my $gene_uniquename = $gene_data->{uniquename};
  my $organism_name = $gene_data->{organism};

  my $key = "$organism_name - $gene_uniquename";

  if (!exists $cache->{$key}) {
    my $organism = $self->find_organism_by_full_name($organism_name);

    $cache->{$key} = $self->find_chado_feature($gene_uniquename, 1, 1, $organism);
  }

  return $cache->{$key};
}

sub get_transcript {
  my $self = shift;
  my $gene = shift;

  return $self->find_chado_feature($gene->uniquename() . ".1", 1, 1, $gene->organism());
}

sub get_genotype {
  my $self = shift;
  my $genotype_identifier = shift;
  my $genotype_name = shift;
  my $genotype_background = shift;
  my $genotype_comment = shift;
  my $alleles = shift;

  if (!defined $alleles) {
    warn "no alleles passed to get_genotype()\n";
    exit 1;
  }

  map {
    my $allele_data = $_;
    my $expression = $allele_data->{expression};
    if ($expression &&
        ($expression eq 'Not assayed' ||
         $expression eq 'Wild type product level')) {
      $allele_data->{expression} = 'Not assayed or wild type';
    }
  } @$alleles;

  my $cached_genotype =
    $self->genotype_cache()->get($genotype_name, $genotype_background, $alleles);

  if ($cached_genotype) {
    return $cached_genotype;
  }

  my $first_allele_data = $alleles->[0];

  if (!$first_allele_data->{allele}) {
    confess "allele data for genotypes must have the form { allele => {...}, " .
      "expression => ... } (where expression is optional) \n details:",
      Dumper([$genotype_identifier, $alleles]);
  }

  my $organism_id = $first_allele_data->{allele}->organism_id();

  state $organism_cache = {};

  my $organism = undef;

  if (!exists $organism_cache->{$organism_id}) {
    # weird and hacky :-(
    # don't materialise the allele organism unless we have to
    $organism_cache->{$organism_id} = $first_allele_data->{allele}->organism();
  }
  $organism = $organism_cache->{$organism_id};

  my $genotype = $self->store_feature($genotype_identifier,
                                      $genotype_name, [], 'genotype',
                                      $organism);

  if ($genotype_background) {
    $self->store_featureprop($genotype, 'genotype_background',
                             $genotype_background);
  }

  if ($genotype_comment) {
    $self->store_featureprop($genotype, 'genotype_comment',
                             $genotype_comment);
  }

  map {
    my $rel = $self->store_feature_rel($_->{allele}, $genotype, 'part_of');
    if ($_->{expression}) {
      $self->store_feature_relationshipprop($rel, 'expression', $_->{expression});
    }
    if ($_->{promoter_gene}) {
      $self->store_feature_relationshipprop($rel, 'promoter_gene', $_->{promoter_gene});
    }
    if ($_->{exogenous_promoter}) {
      $self->store_feature_relationshipprop($rel, 'exogenous_promoter', $_->{exogenous_promoter});
    }
    if ($_->{genotype_locus}) {
      $self->store_feature_relationshipprop($rel, 'genotype_locus', $_->{genotype_locus});
    }
  } @$alleles;

  $self->genotype_cache()->put($genotype_name, $genotype_background, $alleles, $genotype);

  return $genotype;
}

sub _get_genotype_suffix_pg {
  my $self = shift;
  my $dbh = shift;
  my $prefix = shift;

  my $sql = "select max(substring(uniquename from '^$prefix(.*)\$')::integer)+1 from feature where uniquename like '$prefix%'";

  my $sth = $dbh->prepare($sql);

  $sth->execute()
    or die "Couldn't execute query: " . $sth->errstr();

  my @data = $sth->fetchrow_array();

  return $data[0] // 1;
}

sub _get_genotype_suffix_sqlite {
  my $self = shift;
  my $dbh = shift;
  my $prefix = shift;

  my $sql = "select uniquename from feature where uniquename like '$prefix%'";

  my $sth = $dbh->prepare($sql);

  $sth->execute()
    or die "Couldn't execute query: " . $sth->errstr();

  my $max = 0;

  while (my @data = $sth->fetchrow_array()) {
    (my $id = $data[0]) =~ s/pombase.*-(\d+)$/$1/i;
    if ($id > $max) {
      $max = $id;
    }
  }

  return $max + 1;
}

=head2 get_genotype_uniquename

 Usage   : my $uniquename = $self->get_genotype_uniquename();
 Function: return a genotype uniquename that hasn't been used

=cut

sub get_genotype_uniquename {
  my $self = shift;
  my $dbh = $self->chado()->storage()->dbh();

  my $database_name = $self->config()->{database_name};
  my $prefix = "$database_name-genotype-";

  my $new_suffix;

  if (defined $self->{_saved_genotype_uniquename}) {
    $new_suffix = ++$self->{_saved_genotype_uniquename};
  } else {
    if ($self->chado()->storage()->connect_info()->[0] =~ /dbi:SQLite/) {
      $new_suffix = $self->_get_genotype_suffix_sqlite($dbh, $prefix);
    } else {
      $new_suffix = $self->_get_genotype_suffix_pg($dbh, $prefix);
    }

    $self->{_saved_genotype_uniquename} = $new_suffix;
  }

  return "$prefix$new_suffix";
}

sub get_genotype_for_allele {
  my $self = shift;
  my $background = shift;
  my $allele_data = shift;
  my $expression = shift;
  my $promoter_gene = shift;
  my $exogenous_promoter = shift;

  my $allele = $self->get_allele($allele_data);

  my $genotype_identifier = $self->get_genotype_uniquename();

  $expression = undef if $expression && lc $expression eq 'null';

  $expression = 'Not assayed' if $expression && lc $expression eq 'not specified';

  return ($self->get_genotype($genotype_identifier, undef, $background, undef,
                              [{ allele => $allele, expression => $expression,
                                 promoter_gene => $promoter_gene,
                                 exogenous_promoter => $exogenous_promoter }]),
          $allele);
}

sub _get_allele_props {
  my $allele = shift;

  my $prop_rs = $allele->featureprops()->search({}, { prefetch => 'type' });

  my %ret = ();

  while (defined (my $prop = $prop_rs->next())) {
    $ret{$prop->type()->name()} = $prop;
  }

  return %ret;
}

sub fix_expression_allele {
  my $self = shift;
  my $gene_name = shift;
  my $name = shift;
  my $description_ref = shift;
  my $expression_ref = shift;

  if ($$name eq 'noname' and
      grep /^$$description_ref$/, qw(overexpression endogenous knockdown)) {
    if (defined $$expression_ref) {
      die "can't have expression=$$expression_ref AND allele=$$name($description_ref)\n";
    } else {
      $$expression_ref = ucfirst $$description_ref;
      $$description_ref = 'wild type';

      $$name = "$gene_name+";
    }
  }
}

my $whitespace_re = qr([\s\N{ZERO WIDTH SPACE}]+);

sub make_allele_data_from_display_name {
  my $self = shift;
  my $gene_feature = shift;
  my $display_name = shift;
  my $expression_ref = shift;

  if ($display_name =~ /^\s*(.+?)\((.*)\)/) {
    my $name = $1;
    $name =~ s/^$whitespace_re|$whitespace_re$//g;
    my $description = $2;
    $description =~ s/^$whitespace_re|$whitespace_re$//g;
    $self->fix_expression_allele($gene_feature->name(), \$name, \$description, $expression_ref);
    return $self->make_allele_data($name, $description, $gene_feature);
  } else {
    if ($display_name =~ /.*delta$/) {
      $$expression_ref = undef;
      return $self->make_allele_data($display_name, "deletion", $gene_feature);
    } else {
      die qq|allele qualifier "$_" isn't in the form "name(description)"\n|;
    }
  }
}

sub make_allele_data {
  my $self = shift;
  my $name = shift;
  my $description = shift;
  my $gene_feature = shift;

  my $gene_name = $gene_feature->name();
  my $organism = $gene_feature->organism();

  my $allele_type = $self->allele_type_from_desc($description, $gene_name);

  my %ret = (
    name => $name,
    description => $description,
    gene => {
      organism => $organism->genus() . ' ' . $organism->species(),
      uniquename => $gene_feature->uniquename(),
    },
  );

  if ($allele_type) {
    $ret{allele_type} = $allele_type;
  }

  return \%ret;
}

sub _get_allele_session {
  my $self = shift;
  my $allele = shift;

  my $props_rs = $allele->search_featureprops('canto_session');
  my $prop = $props_rs->first();

  if (defined $prop) {
    return $prop->value();
  } else {
    return undef;
  }
}

sub _needs_gene_name_prefix
{
  my $allele_data = shift;

  return PomBase::Chado::FixAlleleNames::allele_name_needs_gene_name($allele_data->{name},
                                                                     $allele_data->{allele_type});
}

=head2 get_allele

 Usage   : with 'PomBase::Role::PhenotypeFeatureFinder';
           my $allele_obj = $self->get_allele($allele_data);
 Function: Return an allele Feature for the given data.  If there is an existing
           allele feature that matches, return it.  If not make a new feature
           and return it.
           If an allele exists with a matching name and type, but no
           description, set the description of the existing allele and return it.
           If the description arg is undef and there is an existing allele with
           the same name, return it.
           If an existing allele has the same description and type, but no
           name, set the name of the existing allele and return it.
           If the name arg is undef and there is an existing allele with
           the same description, return it.

 Args    : $allele_data - a hash ref with these keys:
             gene - a hash ref to pass to get_gene():
                    { uniquename => "...", organism => "Genus species" }
             primary_identifier - the Chado primary identifier for this allele
             name - the allele name eg. cdc11+, cdc11delta, cdc11-31
             description - the allele description,
                           eg. "100-101" (for NT deletion)
                               "K10A" (for AA mutation)
             allele_type - the allele type from the "PomBase allele types" CV

=cut

sub get_allele {
  my $self = shift;
  my $allele_data = shift;

  my $allele;
  my $gene;

  if (!defined $allele_data) {
    croak "no 'allele_data' key passed to get_allele()";
  }

  if (defined $allele_data->{name}) {
    $allele_data->{name} =~ s/^\s+//;
    $allele_data->{name} =~ s/\s+$//;
    $allele_data->{name} =~ s/\N{GREEK CAPITAL LETTER DELTA}|\N{INCREMENT}/delta/g;
  }

  if (defined $allele_data->{description}) {
    $allele_data->{description} =~ s/^\s+//;
    $allele_data->{description} =~ s/\s+$//;
  }

  if ($allele_data->{name} && $allele_data->{gene} &&
      $allele_data->{gene}->{name} && _needs_gene_name_prefix($allele_data)) {
    $allele_data->{name} = $allele_data->{gene}->{name} . '-' . $allele_data->{name};
  }

  if (ref $allele_data->{gene} eq 'HASH') {
    $gene = $self->get_gene($allele_data->{gene});
  } else {
    $gene = $allele_data->{gene};
  }

  my $canto_session = $allele_data->{canto_session};

  my $add_canto_session = sub {
    if (defined $canto_session) {
      my $allele = shift;
      $self->store_featureprop($allele, 'canto_session', $canto_session);
    }
  };

  my $pub = $allele_data->{pub};

  my $add_pub = sub {
    if (defined $pub) {
      my $allele = shift;
      $self->find_or_create_feature_pub($allele, $pub);
    }
  };

  if (exists $allele_data->{primary_identifier} &&
      $allele_data->{primary_identifier} !~ /:($canto_session)-\d+$/) {
    $allele = $self->chado()->resultset('Sequence::Feature')
                   ->find({ uniquename => $allele_data->{primary_identifier},
                            organism_id => $gene->organism()->organism_id() });
    if (!defined $allele) {
      use Data::Dumper;
      $Data::Dumper::Maxdepth = 3;
      die "failed to find allele from: ", Dumper([$allele_data]);
    }

    if ($allele->is_obsolete()) {
      $allele->is_obsolete(0);
      $allele->update();
    }

    return $allele;
  } else {
    my $new_allele_name = $allele_data->{name};
    $new_allele_name = undef if
      defined $new_allele_name && ($new_allele_name eq 'noname' || $new_allele_name eq '');

    my $new_allele_description = $allele_data->{description};
    if ($new_allele_description) {
      $new_allele_description =~ s/[\s\N{ZERO WIDTH SPACE}]*,[\s\N{ZERO WIDTH SPACE}]*/,/g;

      if ($new_allele_description eq 'unknown') {
        $new_allele_description = undef;
      }
    }

    my $new_allele_type = $allele_data->{allele_type};

    $new_allele_type =~ s/\s+/_/g;

    if ($new_allele_type eq 'deletion') {
      $new_allele_description = 'deletion';
    } elsif ($new_allele_type eq 'wild_type') {
      if (!defined $new_allele_description) {
        $new_allele_description = 'wild type';
      }
    } elsif ($new_allele_type eq 'unknown') {
      if (!defined $new_allele_description) {
        $new_allele_description = 'unknown';
      }
    } elsif ($new_allele_type eq 'disruption') {
      if (!defined $new_allele_description) {
        $new_allele_description = 'disruption';
      }
    }

    my $new_primary_identifier = $allele_data->{primary_identifier};

    my $gene_uniquename = $gene->uniquename();
    my $gene_name = $gene->name();

    if ($new_allele_type ne 'wild_type' && $new_allele_type ne 'deletion' &&
          !defined $new_allele_name && !defined $new_allele_description) {
      use Data::Dumper;
      $Data::Dumper::Maxdepth = 3;
      croak "internal error - no name or description passed to get_allele(): " .
        Dumper([$allele_data]);
    }

    if ($new_allele_type eq 'wild_type' && !$new_allele_name) {
      $new_allele_name = ($gene_name || $gene_uniquename) . '+';
    }
    if($new_allele_type eq 'deletion' && !$new_allele_name) {
      $new_allele_name = ($gene_name || $gene_uniquename) . 'delta';
    }

    my $instance_of_cvterm = $self->get_cvterm('pombase_relations', 'instance_of');
    my $existing_rs = $gene->search_related('feature_relationship_objects')
                           ->search({ 'me.type_id' => $instance_of_cvterm->cvterm_id() },
                                    { prefetch => 'subject' })
                           ->search_related('subject');

    if (defined $new_allele_name) {
      if (defined $new_allele_description &&
          $new_allele_name eq $new_allele_description &&
          defined $gene_name) {
        if (PomBase::Chado::FixAlleleNames::allele_name_needs_gene_name($new_allele_name, $new_allele_type)) {
          my $orig_allele_name = $new_allele_name;
          $new_allele_name = "$gene_name-$new_allele_name";
        }
      }

      my $existing_lower_name_rs = $existing_rs->search({ 'LOWER(name)' => lc $new_allele_name });

      my $existing_allele = $existing_lower_name_rs->first();

      if (defined $existing_lower_name_rs->next()) {
        die 'database inconsistency - there exists more than one allele feature ' .
          'with the name "' . $new_allele_name . '"' . "\n";
      }

      if (defined $existing_allele) {
        my $existing_name = $existing_allele->name();
        if ($existing_name ne $new_allele_name) {
          my $canto_session = $self->_get_allele_session($existing_allele);
          my $session_details = "";

          if (defined $canto_session) {
            $session_details = " (from session $canto_session)";
          }

          # the should differ only in case
          warn 'trying to store an allele ' .
            qq(with the name "$new_allele_name" but the name exists with different ) .
            qq(case: "$existing_name"$session_details\n);

          $new_allele_name = $existing_name;
        }

        if ($existing_name eq $new_allele_name) {
          my %props = _get_allele_props($existing_allele);

          my $existing_description = undef;
          if ($props{description}) {
            $existing_description = $props{description}->value();
          }

          my $existing_allele_type = undef;
          if ($props{allele_type}) {
            $existing_allele_type = $props{allele_type}->value();
          }

          if (defined $existing_description && defined $new_allele_description &&
              lc $existing_description eq lc $new_allele_description ||
              !defined $existing_description && !defined $new_allele_description) {
            # descriptions match, same allele so use existing allele
          } else {
            if (!$new_allele_description or $new_allele_description eq 'unknown') {
              # that's OK, just use the previous description
            } else {
              if (!$existing_description or $existing_description eq 'unknown') {
                # set the existing description since we have a better one
                my $existing_description_prop = $props{description};
                if (defined $existing_description_prop) {
                  $existing_description_prop->value($new_allele_description);
                  $existing_description_prop->update();
                } else {
                  $self->store_featureprop($existing_allele, 'description',
                                           $new_allele_description);
                }
              } else {
                my $canto_session = $self->_get_allele_session($existing_allele);
                my $session_details = "";

                if (defined $canto_session) {
                  $session_details = " (from session $canto_session)";
                }

                warn 'description for new allele "' . $new_allele_name . '(' .
                  ($new_allele_description  // 'undefined') . ')" does not ' .
                  'match the existing allele with the same name "' .
                  $new_allele_name . '(' . ($existing_description // 'undefined') . ')"' .
                  "$session_details\n";
              }
            }
          }

          if (defined $existing_allele_type && defined $new_allele_type &&
              lc $existing_allele_type eq lc $new_allele_type ||
              !defined $existing_allele_type && !defined $new_allele_type) {
            # allele_types match, same allele so use existing allele
          } else {
            if (!$new_allele_type or $new_allele_type eq 'unknown') {
              # that's OK, just use the previous allele_type
            } else {
              if (!$existing_allele_type or $existing_allele_type eq 'unknown') {
                # set the existing allele_type since we have a better one
                my $existing_allele_type_prop = $props{allele_type};
                if (defined $existing_allele_type_prop) {
                  $existing_allele_type_prop->value($new_allele_type);
                  $existing_allele_type_prop->update();
                } else {
                  $self->store_featureprop($existing_allele, 'allele_type',
                                           $new_allele_type);
                }
              } else {
                my $canto_session = $self->_get_allele_session($existing_allele);
                my $session_details = "";

                if (defined $canto_session) {
                  $session_details = " (from session $canto_session)";
                }

                warn 'allele_type for new allele "' . $new_allele_name . '(' .
                  ($new_allele_type  // 'undefined') . ')" does not ' .
                  'match the existing allele with the same name "' .
                  $new_allele_name . '(' . ($existing_allele_type // 'undefined') . ')"' .
                  "$session_details\n";
              }
            }
          }

          $add_canto_session->($existing_allele);

          $add_pub->($existing_allele);

          if ($existing_allele->is_obsolete()) {
            $existing_allele->is_obsolete(0);
            $existing_allele->update();
          }

          if (defined $new_primary_identifier) {
            $self->store_featureprop($existing_allele, 'canto_allele_systematic_id',
                                     $new_primary_identifier);
          }

          return $existing_allele;
        }
      } else {
        # try to merge with an existing allele that has no name
        while (defined (my $existing_allele = $existing_rs->next())) {
          next if $existing_allele->name();

          next if $new_allele_type eq 'unknown';

          my %props = _get_allele_props($existing_allele);

          my $existing_description = undef;

          if ($props{description}) {
            $existing_description = $props{description}->value();
          }

          if ($props{allele_type}->value() eq $new_allele_type &&
              (!defined $new_allele_description && !defined $existing_description ||
               (defined $new_allele_description && defined $existing_description) &&
              $new_allele_description eq $existing_description)) {
            $existing_allele->name($new_allele_name);
            $existing_allele->is_obsolete(0);
            $existing_allele->update();

            if (defined $new_primary_identifier) {
              $self->store_featureprop($existing_allele, 'canto_allele_systematic_id',
                                       $new_primary_identifier);
            }

            return $existing_allele;
          }
        }
      }
    } else {
      # no name so check for existing alleles that match our description
      if (defined $new_allele_description && $new_allele_description eq 'unknown') {
        # we can have multiple alleles with no name and the description "unknown"
      } else {
        while (defined (my $existing_allele = $existing_rs->next())) {
          my %props = _get_allele_props($existing_allele);

          my $existing_description = undef;

          if ($props{description}) {
            $existing_description = $props{description}->value();
          }

          if (!defined $new_allele_description && !defined $existing_description) {
            if ($existing_allele->is_obsolete()) {
              $existing_allele->is_obsolete(0);
              $existing_allele->update();
            }

            if (defined $new_primary_identifier) {
              $self->store_featureprop($existing_allele, 'canto_allele_systematic_id',
                                       $new_primary_identifier);
            }

            return $existing_allele;
          }

          if ((defined $new_allele_description && defined $existing_description) &&
              $new_allele_description eq $existing_description) {
            if ($existing_allele->is_obsolete()) {
              $existing_allele->is_obsolete(0);
              $existing_allele->update();
            }

            if (defined $new_primary_identifier) {
              $self->store_featureprop($existing_allele, 'canto_allele_systematic_id',
                                       $new_primary_identifier);
            }

            return $existing_allele;
          }
        }
      }
    }

    # fall through - no allele exists with matching name or description
    my $new_uniquename = $self->get_new_uniquename($gene_uniquename . ':allele-', 1);
    $allele = $self->store_feature($new_uniquename,
                                   $new_allele_name, [], 'allele',
                                   $gene->organism());

    die "store_feature() failed uniquename: $new_uniquename" unless $allele;

    $self->store_feature_rel($allele, $gene, $instance_of_cvterm);

    if (defined $new_allele_description) {
      $self->store_featureprop($allele, 'description', $new_allele_description);
    }

    $add_canto_session->($allele);

    $add_pub->($allele);

    if (defined $new_allele_type && length $new_allele_type > 0) {
      if (!exists $self->allele_types()->{$new_allele_type}) {
        die "no such allele type: $new_allele_type\n";
      }
      $self->store_featureprop($allele, allele_type => $new_allele_type);
    } else {
      die "no allele_type for: $new_uniquename\n";
    }

    if (defined $new_primary_identifier) {
      $self->store_featureprop($allele, 'canto_allele_systematic_id',
                               $new_primary_identifier);
    }

    return $allele;
  }
}

1;
