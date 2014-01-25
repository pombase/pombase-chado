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

use perl5i::2;
use Moose;

use List::Gen 'iterate';

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';
with 'PomBase::Role::ExtensionDisplayer';

my $ext_cv_name = 'PomBase annotation extension terms';

method _get_allele_details
{
  my %synonyms = ();

  my $syn_rs = $self->chado()->resultset('Sequence::FeatureSynonym')->
    search({ 'feature.organism_id' => $self->organism()->organism_id(),
             is_current => 1, },
           { join => 'feature', prefetch => [ 'synonym' ] });

  map {
    push @{$synonyms{$_->feature_id()}}, $_->synonym()->name();
  } $syn_rs->all();

  my %statuses = ();

  my $statuses_rs = $self->chado()->resultset('Sequence::FeatureCvterm')->
    search({ 'cv.name' => 'PomBase gene characterisation status' },
           { join => { cvterm => 'cv' },
             prefetch => [ 'cvterm', 'feature' ] });

  map {
    my $uniquename = $_->feature()->uniquename();
    $uniquename =~ s/\.\d+:pep$//;
    $statuses{$uniquename} = $_->cvterm()->name();
  } $statuses_rs->all();

  my %featureprops = ();

  my $fprops_rs = $self->chado()->resultset('Sequence::Featureprop')
    ->search({}, { prefetch => 'type' });

  while (defined (my $prop = $fprops_rs->next())) {
    $featureprops{$prop->feature_id()}->{$prop->type()->name()} = $prop->value();
  }

  my %ret_map = ();

  my $gene_rs = $self->chado()->resultset('Sequence::FeatureRelationship')->
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
          'type_2.name' => 'instance_of',
         },
       },
      {
        join => [ { subject => 'type' }, 'type', { object => 'type' } ],
        prefetch => [ { subject => 'type' }, { object => 'type' }, 'type' ] });

  map {
    my $rel = $_;
    my $object = $rel->object();
    my $type = $rel->type();

    if (defined $ret_map{$rel->subject_id()}->{gene}) {
      die "feature has two instance_of parents: ", $rel->subject()->uniquename(),
        " <-> ", $rel->object()->uniquename(),
        " (", $rel->object()->feature_id(), ")\n";
    } else {
      $ret_map{$rel->subject_id()} = {
        gene => $object,
        type => $object->type()->name(),
        transcript_type => $subject->type()->name(),
        synonyms => $synonyms{$object->feature_id()} // [],
        status => $statuses{$object->uniquename()} // '',
        %{$featureprops{$rel->subject_id()} // {}},
      };
    }
  } $gene_rs->all();

  return %ret_map;
}

method _lookup_term($term_id) {
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

func _fix_date($date) {
  if ($date =~ /(\d+)-(\d+)-(\d+)/) {
    return "$1$2$3";
  } else {
    return $date;
  }
}

func _safe_join($expr, $array)
{
  if (defined $array) {
    return join $expr, @{$array};
  } else {
    return '';
  }
}

method retrieve() {
  my $chado = $self->chado();
  my $config = $self->config();

  my $db_name = $self->config()->{db_name_for_cv};
  my $taxon = $self->organism_taxonid();

  my %feature_details = $self->_get_allele_details();

  my $phenotype_cv_name = $config->{phenotype_cv_name};
  my $parental_strain = $config->{parental_strain}->{$self->organism_taxonid()};

  my $it = do {
    my $cvterm_rs =
      $chado->resultset('Cv::Cvterm')->search({ -or =>
                                                  [
                                                    'cv.name' => $phenotype_cv_name,
                                                    'cv.name' => $ext_cv_name,
                                                  ]
                                                },
                                              { join => 'cv' });

    my $feature_cvterm_rs =
      $chado->resultset('Sequence::FeatureCvterm')->search(
        {
          'me.cvterm_id' => { -in => $cvterm_rs->get_column('cvterm_id')->as_query() }
        });

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

    iterate {
    ROW: {
      my $row = $results->next();

      if (defined $row) {
        my ($extensions, $base_cvterm) = $self->make_gaf_extension($row);

        my $fc_id = $row->feature_cvterm_id();
        my %row_fc_props = %{$fc_props{$fc_id}};
        my $cvterm = $base_cvterm // $row->cvterm();

        my $feature = $row->feature();
        my $details = $feature_details{$feature->feature_id()};

        if (!defined $details) {
          warn "can't find details for: ", $feature->uniquename(), " (id: ",
            $feature->feature_id(), ")\n";
          goto ROW;
        }

        if ($details->{type} ne 'gene') {
          warn "ignoring allele ", $feature->uniquename(), " for ",
            $details->{gene}->uniquename(), " - not a gene\n";
          goto ROW;
        }

        my $dbxref = $cvterm->dbxref();
        my $id = $dbxref->db()->name() . ':' . $dbxref->accession();
        my $evidence = _safe_join('|', $row_fc_props{evidence});
        my $evidence_code;
        if (defined $evidence && length $evidence > 0) {
          if (defined $self->config()->{evidence_types}->{$evidence}) {
            $evidence_code = $evidence;
          } else {
            $evidence_code = $self->evidence_to_code()->{$evidence};
            if (!defined $evidence_code) {
              $evidence_code = $self->evidence_to_code()->{ucfirst lc $evidence};
              if (!defined $evidence_code) {
                warn qq|cannot find the evidence code for "$evidence"|;
                goto ROW;
              }
            }
          }
        } else {
          warn "no evidence for ", $feature->uniquename(), " <-> ", $cvterm->name() , "\n";
          $evidence_code = "";
        }

        my $pub = $row->pub();
        my $gene = $details->{gene} // die "no gene for ", $feature->uniquename();
        my $gene_uniquename = $gene->uniquename();
        my $gene_name = $gene->name() // $gene_uniquename;
        my $synonyms_ref = $details->{synonyms} // [];
        my $synonyms = join '|', @{$synonyms_ref};
        my $product = $details->{product} // '';

        my $date = _safe_join('|', [map { _fix_date($_) } @{$row_fc_props{date}}]);
        my $gene_product_form_id = _safe_join('|', $row_fc_props{gene_product_form_id});
        my $assigned_by = _safe_join('|', $row_fc_props{assigned_by});

        my $allele_description = _safe_join(',', $row_fc_props{description});
        my $allele_type = $details->{allele_type};
        my $condition = _safe_join(',', $row_fc_props{condition});
        my $penetrance = _safe_join(',', $row_fc_props{penetrance});
        my $expressivity = _safe_join(',', $row_fc_props{expressivity});

        my $expression = $details->{expression} // '';

        return [
          $db_name,
          $gene_uniquename, $id, $gene_name,
          $allele_description,
          $expression, $parental_strain,
          'not available',
          'not available',
          $gene_name, $feature->name() // '',
          $synonyms,
          $allele_type,
          $evidence_code, $condition,
          $penetrance, $expressivity,
          $extensions // '', $pub->uniquename(),
          $taxon, $date,
          ]
      }
    }
    };
  };
}

method header
{
  return '';
}

method format_result($res)
{
  my $line = (join "\t", @$res);

  die "dubious $line!" if $line =~ /dubious/;

  return (join "\t", @$res);
}
