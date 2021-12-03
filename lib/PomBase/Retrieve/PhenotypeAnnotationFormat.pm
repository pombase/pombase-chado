package PomBase::Retrieve::PhenotypeAnnotationFormat;

=head1 NAME

PomBase::Retrieve::PhenotypeAnnotationFormat - Code for dumping
            phenotypes and their annotations

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::PhenotypeAnnotationFormat

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

use Getopt::Long qw(GetOptionsFromArray :config pass_through);

use Moose;

use Iterator::Simple qw(iterator);

use PomBase::Chado;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';
with 'PomBase::Role::ExtensionDisplayer';

my $ext_cv_name = 'PomBase annotation extension terms';
my $fypo_extensions_cv_name = 'fypo_extensions';

has fypo_extension_termids => (is => 'ro', init_arg => undef,
                               lazy_build => 1);

has use_eco_evidence_codes => (is => 'rw');

sub _build_fypo_extension_termids
{
  my $self = shift;

  my $chado = $self->chado();

  my $ext_rs = $chado->resultset('Cv::Cvterm')->search(
    {
      'cv.name' => $fypo_extensions_cv_name,
    },
    {
      join => [ 'cv', { dbxref => 'db' } ],
    });

  my %fypo_extension_termids = ();

  while (defined (my $ext = $ext_rs->next())) {
    my $termid = PomBase::Chado::id_of_cvterm($ext);
    $fypo_extension_termids{$ext->name()} = $termid;
  }

  return \%fypo_extension_termids
}

sub BUILDARGS
{
  my $class = shift;
  my %args = @_;

  my $use_eco_evidence_codes = 0;

  my @opt_config = ('use-eco-evidence-codes' => \$use_eco_evidence_codes);

  if (!GetOptionsFromArray($args{options}, @opt_config)) {
    croak "option parsing failed";
  }

  $args{use_eco_evidence_codes} = $use_eco_evidence_codes;

  return \%args;
}

sub _get_allele_gene_map {
  my $self = shift;
  my %allele_gene_map = ();

  my $allele_gene_rs = $self->chado()->resultset('Sequence::FeatureRelationship')->
    search(
      {
        -and => {
          'subject.organism_id' => $self->organism()->organism_id(),
          'type.name' => 'allele',
          'type_2.name' => 'instance_of',
          -or => [
            'type_3.name' => 'gene',
            'type_3.name' => 'pseudogene',
          ],
        },
      },
      {
        join => [ { subject => 'type' }, 'type', { object => 'type' } ],
        prefetch => [ { subject => 'type' }, { object => 'type' }, 'type' ] });

  while (defined (my $rel = $allele_gene_rs->next())) {
    my $allele = $rel->subject();
    my $gene = $rel->object();
    my $type = $rel->type();

    $allele_gene_map{$allele->uniquename()} = {
      gene_uniquename => $gene->uniquename(),
      gene_name => $gene->name(),
    }
  }

  return %allele_gene_map;
}

sub _get_allele_props {
  my $self = shift;
  my %allele_props = ();

  my $allele_props_rs =
    $self->chado()->resultset('Sequence::Featureprop')
      ->search({ 'type_2.name' => 'allele' }, { join => ['type', {  feature => 'type' }] });

  while (defined (my $prop = $allele_props_rs->next())) {
    $allele_props{$prop->feature()->uniquename()}->{$prop->type()->name()} = $prop->value();
  }

  return %allele_props;
}

sub _get_genotype_allele_props {
  my $self = shift;
  my $genotype_allele_rs = shift;

  my %genotype_allele_props = ();

  my $genotype_allele_prop_rs = $self->chado()->resultset('Sequence::FeatureRelationshipprop')->
    search(
      {
        'feature_relationship_id' => {
          -in => $genotype_allele_rs->get_column('feature_relationship_id')->as_query(),
        },
      },
      {
        prefetch => 'type',
      });

  while (defined (my $prop = $genotype_allele_prop_rs->next())) {
    $genotype_allele_props{$prop->feature_relationship_id()}
      ->{$prop->type()->name()} = $prop->value();
  }

  return %genotype_allele_props;
}

sub _get_genotype_details {
  my $self = shift;
  my $genotype_feature_rs = shift;

  my %allele_gene_map = $self->_get_allele_gene_map();

  my %allele_props = $self->_get_allele_props();

  my %ret_map = ();

  my $genotype_allele_rs = $self->chado()->resultset('Sequence::FeatureRelationship')->
    search(
      {
        -and => {
          'object.organism_id' => $self->organism()->organism_id(),
          'type.name' => 'allele',
          'type_2.name' => 'part_of',
          'object.feature_id' => {
            -in => $genotype_feature_rs->get_column('feature_id')->as_query(),
          },
         },
       },
      {
        join => [ { subject => 'type' }, 'type', { object => 'type' } ],
        prefetch => [ { subject => 'type' }, 'type', { object => 'type' } ] });

  my %genotype_allele_props = $self->_get_genotype_allele_props($genotype_allele_rs);

  map {
    my $rel = $_;
    my $allele = $rel->subject();
    my $genotype = $rel->object();

    push @{$ret_map{$genotype->uniquename()}},
      {
        expression => $genotype_allele_props{$rel->feature_relationship_id()}->{expression},
        %{$allele_gene_map{$allele->uniquename()}},
        allele_uniquename => $allele->uniquename(),
        allele_name => $allele->name(),
        %{$allele_props{$allele->uniquename} // {}},
      };
  } $genotype_allele_rs->all();

  return %ret_map;
}

sub _lookup_term {
  my $self = shift;
  my $term_id = shift;

  state $cache = {};

  if (exists $cache->{$term_id}) {
    return $cache->{$term_id};
  } else {
    my $chado = $self->chado();
    my $term = $chado->resultset('Cv::Cvterm')->find($term_id);
    $cache->{$term_id} = $term;
    return $term;
  }
}

sub _safe_join {
  my $expr = shift;
  my $array = shift;

  if (defined $array) {
    return join $expr, @{$array};
  } else {
    return '';
  }
}

sub retrieve {
  my $self = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $db_name = $self->config()->{database_name};
  my $taxon = $self->organism_taxonid();

  my $phenotype_cv_name = $config->{phenotype_cv_name};
  my $parental_strain = $config->{parental_strain}->{$self->organism_taxonid()};

  my $phenotype_cv_rs =
    $chado->resultset('Cv::Cv')->search({ 'cv.name' => $phenotype_cv_name });

  my %fypo_extension_termids = %{$self->fypo_extension_termids()};

  my $from_extension_cv_terms_rs =
    $chado->resultset('Cv::Cvterm')->search(
      {
        'cv.name' => $ext_cv_name,
      },
      {
        join => [ 'cv', { cvterm_relationship_subjects => 'object' } ],
        where => \"object.cv_id in (select cv_id from cv obj_cv where obj_cv.name = '$phenotype_cv_name')",
      });

  my $cvterm_rs =
    $chado->resultset('Cv::Cvterm')->search({ -or =>
                                                [
                                                  'cv.name' => $phenotype_cv_name,
                                                  cvterm_id => {
                                                    -in => $from_extension_cv_terms_rs->get_column('cvterm_id')->as_query(),
                                                  }
                                                ],
                                              },
                                            {
                                              join => 'cv' });

  my %ext_parent_values = ();

  my $ext_parents_rs =
    $chado->resultset('Cv::Cvterm')->search(
      {
        'me.cvterm_id' => {
          -in => $from_extension_cv_terms_rs->get_column('cvterm_id')->as_query(),
        },
        -or => [
          'type.name' => 'has_penetrance',
          'type.name' => 'has_severity',
          ],
      },
      {
        join => { cvterm_relationship_subjects => [ 'type', 'object' ] },
      }
    );

  while (defined (my $ext_parent = $ext_parents_rs->next())) {
    for my $ext_rel ($ext_parent->cvterm_relationship_subjects()) {
      # we need has_severity or has_penetrance
      my $rel_name = $ext_rel->type()->name();

      next unless $rel_name eq 'has_severity' or $rel_name eq 'has_penetrance';

      # "high", "low", ...
      my $ext_name = $ext_rel->object()->name();

      my $value = $fypo_extension_termids{$ext_name};

      if (!defined $value) {
        warn "'$ext_name' is not a valid penetrance/severity in term: ",
          $ext_parent->name(), "\n";
      } else {
        $ext_parent_values{$ext_parent->cvterm_id()}{$rel_name}{$value} = 1;
      }
    }
  }

  my $ext_cvtermprops_rs =
    $chado->resultset('Cv::Cvtermprop')->search(
      {
        'me.cvterm_id' => {
          -in => $from_extension_cv_terms_rs->get_column('cvterm_id')->as_query(),
        },
        -or => [
          'type.name' => 'annotation_extension_relation-has_penetrance',
          'type.name' => 'annotation_extension_relation-has_severity',
        ],
      },
      {
        join => 'type'
      }
    );

  while (defined (my $ext_prop = $ext_cvtermprops_rs->next())) {
    my $rel_name = $ext_prop->type->name() =~ s/annotation_extension_relation-//r;
    $ext_parent_values{$ext_prop->cvterm_id()}{$rel_name}{$ext_prop->value()} = 1;
  }

  my $feature_cvterm_rs =
      $chado->resultset('Sequence::FeatureCvterm')->search(
        {
          'me.cvterm_id' => { -in => $cvterm_rs->get_column('cvterm_id')->as_query() },
          'feature.organism_id' => $self->organism()->organism_id(),
          'type.name' => 'genotype',
        },
        {
          join => { 'feature' => 'type' },
        });

  my $genotype_rs = $feature_cvterm_rs->search_related('feature');

  my %genotype_details = $self->_get_genotype_details($genotype_rs);

  my $it = do {
    my %fc_props = ();

    my $fc_props_rs = $feature_cvterm_rs->search_related('feature_cvtermprops');
    my %types_by_id = ();

    while (defined (my $prop = $fc_props_rs->next())) {
      my $type = $self->_lookup_term($prop->type_id());
      push @{$fc_props{$prop->feature_cvterm_id()}->{$type->name()}}, $prop->value();
    }

    my $results =
      $feature_cvterm_rs->search({},
        {
          prefetch => [ 'feature', 'pub', { cvterm => [ 'cv', { dbxref => 'db' } ] } ]
        },
      );

    iterator {
    ROW: {
      my $row = $results->next();

      if (defined $row) {
        my ($extensions, $base_cvterm) = $self->make_gaf_extension($row);

        # we have separate columns for these:
        if ($extensions) {
          $extensions =~ s/(has_penetrance|has_severity)\([^\)]+\),?//g;
          $extensions =~ s/,$//;
        }

        my $fc_id = $row->feature_cvterm_id();
        my $fc_props_ref = $fc_props{$fc_id};
        my %row_fc_props = %{$fc_props_ref // {}};
        my $cvterm = $base_cvterm // $row->cvterm();

        my $genotype = $row->feature();
        my $details = $genotype_details{$genotype->uniquename()};

        if (!defined $details) {
          warn "can't find details for: ", $genotype->uniquename(), " (id: ",
            $genotype->feature_id(), ")\n";
          goto ROW;
        }

        if (@{$details} > 1) {
          goto ROW;
        }

        my $dbxref = $cvterm->dbxref();
        my $id = $dbxref->db()->name() . ':' . $dbxref->accession();
        my $evidence_code;

        if ($self->use_eco_evidence_codes()) {
          $evidence_code = _safe_join('|', $row_fc_props{eco_evidence});

          if (length $evidence_code == 0) {
            warn "no ECO evidence for ", $genotype->uniquename(), " <-> ", $cvterm->name() , " - skipping\n";
            goto ROW;
          }
        } else {
          my $evidence = _safe_join('|', $row_fc_props{evidence});
          if (defined $evidence && length $evidence > 0) {
            if (defined $self->config()->{evidence_types}->{$evidence}) {
              $evidence_code = $evidence;
            } else {
              # maybe the name is used instead of the code
              $evidence_code = $config->{evidence_name_to_code}->{lc $evidence};
              if (!defined $evidence_code) {
                warn qq|cannot find the evidence code for "$evidence"|;
                goto ROW;
              }
            }
          } else {
            warn "no evidence for ", $genotype->uniquename(), " <-> ", $cvterm->name() , "\n";
            $evidence_code = "";
          }
        }

        my $pub = $row->pub();

        my $first_allele = $details->[0];

        my $gene_uniquename = $first_allele->{gene_uniquename};
        my $gene_name = $first_allele->{gene_name} // $gene_uniquename;
        my $product = $first_allele->{product} // '';

        my $date = _safe_join('|', $row_fc_props{date});
        my $gene_product_form_id = _safe_join('|', $row_fc_props{gene_product_form_id});
        my $assigned_by = _safe_join('|', $row_fc_props{assigned_by});

        my $allele_description = $first_allele->{description} // '';
        my $allele_type = $first_allele->{allele_type};
        my $condition = _safe_join(',', $row_fc_props{condition});

        my $penetrance = _safe_join(',', [keys %{$ext_parent_values{$row->cvterm_id()}{has_penetrance}}]);
        my $severity = _safe_join(',', [keys %{$ext_parent_values{$row->cvterm_id()}{has_severity}}]);

        my $expression = $first_allele->{expression} // '';

        my $residue = $row_fc_props{residue};

        if ($residue) {
          my $residue_str = join ',', @$residue;
          if ($extensions && length $extensions > 0) {
            $extensions .= ",residue($residue_str)";
          } else {
            $extensions = "residue($residue_str)";
          }
        }

        return [
          $db_name,
          $gene_uniquename, $id,
          $allele_description,
          $expression, $parental_strain,
          '',
          '',
          $gene_name,
          $first_allele->{allele_name} // '',
          '',
          $allele_type,
          $evidence_code, $condition,
          $penetrance, $severity,
          $extensions // '', $pub->uniquename(),
          $taxon, $date,
        ]
      }
    }
    };
  };
}

sub header {
  my $self = shift;
  return (join "\t",
          ('#Database name',
           'Gene systematic ID',
           'FYPO ID',
           'Allele description',
           'Expression',
           'Parental strain',
           'Strain name (background)',
           'Genotype description',
           'Gene name',
           'Allele name',
           'Allele synonym',
           'Allele type',
           'Evidence',
           'Condition',
           'Penetrance',
           'Severity',
           'Extension',
           'Reference',
           'Taxon',
           'Date',
         )) . "\n";
}

sub format_result {
  my $self = shift;
  my $res = shift;

  my $line = (join "\t", @$res);

  die "dubious $line!" if $line =~ /dubious/;

  return (join "\t", @$res);
}

1;
