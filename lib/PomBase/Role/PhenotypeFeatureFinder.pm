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

use perl5i::2;
use Moose::Role;

requires 'get_cvterm';
requires 'find_chado_feature';
requires 'find_organism_by_full_name';
requires 'store_feature_rel';

has allele_types => (is => 'rw', init_arg => undef, lazy_build => 1);

method _build_allele_types
{
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
method get_gene($gene_data)
{
  if (!defined $gene_data) {
    croak 'no $gene_data passed to get_gene()';
  }
  my $gene_uniquename = $gene_data->{uniquename};
  my $organism_name = $gene_data->{organism};
  my $organism = $self->find_organism_by_full_name($organism_name);

  return $self->find_chado_feature($gene_uniquename, 1, 1, $organism);
}

method get_transcript($gene_data)
{
  my $gene_uniquename = $gene_data->{uniquename};
  my $organism_name = $gene_data->{organism};
  my $organism = $self->find_organism_by_full_name($organism_name);

  return $self->find_chado_feature("$gene_uniquename.1", 1, 1, $organism);
}

func _get_allele_description($allele) {
  my $description_prop = $allele->search_featureprops('description')->first();
  if (defined $description_prop) {
    return ($description_prop->value(), $description_prop);
  } else {
    return ();
  }
}

func _could_be_aa_mutation_desc($description)
{
  return $description =~ /^[a-z]+\d+[a-z]+$/i;
}

func _is_na_mutation_desc($description)
{
  return $description =~ /^[atgc]+\d+[atgc]+$/i;
}

=head2 is_aa_mutation_desc

 Usage   : if ($self->is_aa_mutation_desc($description)) { ... }
 Function: Return true if the $description looks like an amino acid
           mutation, like; "K10A" and doesn't look like a nucleotide
           mutation description like "A10T"

=cut
method is_aa_mutation_desc($description)
{
  return 0 unless defined $description;

  $description = $description->trim();

  my $seen_aa_desc = 0;

  if ($description =~ /,/) {
    for my $bit (split /,/, $description) {
      $bit = $bit->trim();
      if (_could_be_aa_mutation_desc($bit)) {
        if (!_is_na_mutation_desc($bit)) {
          $seen_aa_desc = 1;
        }
      } else {
        return 0;
      }
    }

    return $seen_aa_desc;
  }

  return _could_be_aa_mutation_desc($description) && !_is_na_mutation_desc($description);
}

method allele_type_from_desc($description, $gene_name)
{
  $description = $description->trim();
  if (grep { $_ eq $description } ('deletion', 'wild_type', 'wild type', 'unknown', 'other', 'unrecorded')) {
    return ($description =~ s/\s+/_/r);
  } else {
    if ($self->is_aa_mutation_desc($description)) {
      return 'amino_acid_mutation';
    } else {
      if ($description =~ /^[A-Z]\d+->(amber|ochre|opal|stop)$/i) {
        return 'nonsense_mutation';
      } else {
        if (defined $gene_name && $description =~ /^$gene_name/) {
          return 'other';
        }
      }
    }
  }

  return undef;
}

method fix_expression_allele($name, $description_ref, $expression_ref)
{
  if ($name eq 'noname' and
      grep /^$$description_ref$/, qw(overexpression endogenous knockdown)) {
    if (defined $$expression_ref) {
      die "can't have expression=$$expression_ref AND allele=$name($description_ref)\n";
    } else {
      $$expression_ref = ucfirst $$description_ref;
      $$description_ref = 'wild type';
    }
  }
}

my $whitespace_re = "\\s\N{ZERO WIDTH SPACE}";

method make_allele_data_from_display_name($gene_feature, $display_name, $expression_ref) {
  if ($display_name =~ /^\s*(.+?)\((.*)\)/) {
    my $name = $1;
    $name = $name->trim($whitespace_re);
    my $description = $2;
    $description = $description->trim($whitespace_re);
    $self->fix_expression_allele($name, \$description, $expression_ref);
    return $self->make_allele_data($name, $description, $gene_feature);
  } else {
    if ($display_name =~ /.*delta$/) {
      return $self->make_allele_data($display_name, "deletion", $gene_feature);
    } else {
      die qq|allele qualifier "$_" isn't in the form "name(description)"\n|;
    }
  }
}

method make_allele_data($name, $description, $gene_feature) {
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

method _get_allele_session($allele)
{
  my $props_rs = $allele->search_featureprops('canto_session');
  my $prop = $props_rs->first();

  if (defined $prop) {
    return $prop->value();
  } else {
    return undef;
  }
}

=head2 get_allele

 Usage   : with 'PomBase::Role::PhenotypeFeatureFinder';
           my $allele_obj = $self->get_allele($allele_data);
 Function: Return an allele Feature for the given data
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

method get_allele($allele_data)
{
  my $allele;
  my $gene;

  if (!defined $allele_data) {
    croak "no 'allele_data' key passed to get_allele()";
  }

  if (ref $allele_data->{gene} eq 'HASH') {
    $gene = $self->get_gene($allele_data->{gene});
  } else {
    $gene = $allele_data->{gene};
  }

  if (exists $allele_data->{primary_identifier}) {
    $allele = $self->chado()->resultset('Sequence::Feature')
                   ->find({ uniquename => $allele_data->{primary_identifier},
                            organism_id => $gene->organism()->organism_id() });
    if (!defined $allele) {
      use Data::Dumper;
      die "failed to find allele from: ", Dumper([$allele_data]);
    }

    return $allele;
  } else {
    my $new_allele_name = $allele_data->{name};
    $new_allele_name = undef if defined $new_allele_name && $new_allele_name eq 'noname';

    my $new_allele_description = $allele_data->{description};
    $new_allele_description =~ s/[\s\N{ZERO WIDTH SPACE}]*,[\s\N{ZERO WIDTH SPACE}]*/,/g;

    if (!defined $new_allele_name && !defined $new_allele_description) {
      croak "internal error - no name or description passed to get_allele()";
    }

    my $gene_uniquename = $gene->uniquename();
    my $instance_of_cvterm = $self->get_cvterm('relationship', 'instance_of');
    my $existing_rs = $gene->search_related('feature_relationship_objects')
                           ->search({ 'me.type_id' => $instance_of_cvterm->cvterm_id() },
                                    { prefetch => 'subject' })
                           ->search_related('subject');

    if (defined $new_allele_name) {
      $existing_rs = $existing_rs->search({ 'LOWER(name)' => lc $new_allele_name });

      if ($existing_rs->count() > 1) {
        die 'database inconsistency - there exists more than one allele feature ' .
          'with the name "' . $new_allele_name . '"' . "\n";
      }

      my $existing_allele = $existing_rs->first();

      if (defined $existing_allele) {
        my $existing_name = $existing_allele->name();
        if ($existing_name ne $new_allele_name) {
          my $canto_session = $self->_get_allele_session($existing_allele);
          my $session_details = "";

          if (defined $canto_session) {
            $session_details = " (from session $canto_session)";
          }

          # the should differ only in case
          die 'trying to store an allele ' .
            qq(with the name "$new_allele_name" but the name exists with different ) .
            qq(case: "$existing_name"$session_details\n);
        }

        my ($existing_description, $existing_description_prop) =
          _get_allele_description($existing_allele);

        if ($existing_allele->name() eq $new_allele_name) {
          if (defined $existing_description && defined $new_allele_description &&
              lc $existing_description eq lc $new_allele_description ||
              !defined $existing_description && !defined $new_allele_description) {
            # descriptions match - same allele
            return $existing_allele;
          } else {
            if ($new_allele_description eq 'unknown') {
              # that's OK, just use the previous description
              return $existing_allele;
            }

            if ($existing_description eq 'unknown') {
              # that's OK, just set the existing description
              if (defined $existing_description_prop) {
                $existing_description_prop->value($new_allele_description);
                $existing_description_prop->update();
              } else {
                $self->store_featureprop($existing_allele, 'description',
                                         $new_allele_description);
              }
              return $existing_allele;
            }

            my $canto_session = $self->_get_allele_session($existing_allele);
            my $session_details = "";

            if (defined $canto_session) {
              $session_details = " (from session $canto_session)";
            }

            die 'description for new allele "' . $new_allele_name . '(' .
              ($new_allele_description  // 'undefined') . ')" does not ' .
              'match the existing allele with the same name "' .
              $new_allele_name . '(' . ($existing_description // 'undefined') . ')"' .
              "$session_details\n";
          }
        }
      }
    } else {
      # no name so check for existing alleles that match our description
      if ($new_allele_description eq 'unknown') {
        # we can have multiple alleles with no name and the description "unknown"
      } else {
        while (defined (my $existing_allele = $existing_rs->next())) {
          my ($existing_description, $existing_description_prop) =
            _get_allele_description($existing_allele);

          if ($new_allele_description eq $existing_description) {
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

    $self->store_feature_rel($allele, $gene, $instance_of_cvterm);

    if (defined $new_allele_description) {
      $self->store_featureprop($allele, 'description', $new_allele_description);
    }

    my $canto_session = $allele_data->{canto_session};

    if (defined $canto_session) {
      $self->store_featureprop($allele, 'canto_session', $canto_session);
    }

    my $allele_type = $allele_data->{allele_type};

    if (defined $allele_type && length $allele_type > 0) {
      if (!exists $self->allele_types()->{$allele_type}) {
        die "no such allele type: $allele_type\n";
      }
      $self->store_featureprop($allele, allele_type => $allele_type);
    } else {
      die "no allele_type for: $new_uniquename\n";
    }

    return $allele;
  }
}

1;
