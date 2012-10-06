package PomBase::Retrieve::GeneAssociationFile;

=head1 NAME

PomBase::Retrieve::GeneAssociationFile - Retrieve GO annotation from
           Chado and generate a GAF format file

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::GeneAssociationFile

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
use feature 'state';

use List::Gen 'iterate';

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Retriever';
with 'PomBase::Role::ExtensionDisplayer';

my @go_cv_names = qw(biological_process cellular_component molecular_function);
my $ext_cv_name = 'PomBase annotation extension terms';

has options => (is => 'ro', isa => 'ArrayRef');

method BUILD
{
  my $chado = $self->chado();

  my $organism_taxonid = undef;

  my @opt_config = ("organism-taxon-id=s" => \$organism_taxonid);
  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $organism_taxonid) {
    die "no --organism-taxon-id argument\n";
  }

  my %evidence_to_code = ();

  while (my ($code, $details) = each %{$self->config()->{evidence_types}}) {
    my $ev_name = $details->{name} // $code;
    $evidence_to_code{$ev_name} = $code;
  }

  $self->{_evidence_to_code} = \%evidence_to_code;

  $self->{_organism_taxonid} = $organism_taxonid;

  my $taxonid_cvterm_query = $self->chado()->resultset('Cv::Cvterm')->
     search({ name => 'taxon_id' })->get_column('cvterm_id')->as_query();

  $self->{_organism} = $self->chado()->resultset('Organism::Organismprop')->
    search({ type_id => { -in => $taxonid_cvterm_query },
             value => $organism_taxonid })->
    search_related('organism')->first();

  die "can't find organism for taxon $organism_taxonid\n"
    unless $self->{_organism};
}

method _get_feature_details
{
  my %synonyms = ();

  my $syn_rs = $self->chado()->resultset('Sequence::FeatureSynonym')->
    search({ 'feature.organism_id' => $self->{_organism}->organism_id() },
           { join => 'feature', prefetch => [ 'synonym' ] });

  map {
    push @{$synonyms{$_->feature_id()}}, $_->synonym()->name();
  } $syn_rs->all();

  my %products = ();

  my $products_rs = $self->chado()->resultset('Sequence::FeatureCvterm')->
    search({ 'cv.name' => 'PomBase gene products' },
           { join => { cvterm => 'cv' },
             prefetch => [ 'cvterm', 'feature' ] });

  map {
    my $uniquename = $_->feature()->uniquename();
    $uniquename =~ s/\.\d+:pep$//;
    $products{$uniquename} = $_->cvterm()->name();
  } $products_rs->all();

  my %ret_map = ();

  my $gene_rs = $self->chado()->resultset('Sequence::FeatureRelationship')->
    search(
      {
        -and => {
          'subject.organism_id' => $self->{_organism}->organism_id(),
          -or => [
            'type_2.name' => 'gene',
            'type_2.name' => 'pseudogene',
          ],
          'type.name' => 'part_of',
        },
      },
      {
        join => [ 'subject', 'type', { object => 'type' } ],
        prefetch => [ 'subject', { object => 'type' }, 'type' ] });

  map {
    my $rel = $_;
    my $object = $rel->object();
    my $type = $rel->type();
    if ($type->name() eq 'part_of') {
      if (defined $ret_map{$rel->subject_id()}->{gene}) {
        die "feature has two part_of parents";
      } else {
        $ret_map{$rel->subject_id()} = {
          gene => $object,
          type => $object->type()->name(),
          synonyms => $synonyms{$object->feature_id()},
          product => $products{$object->uniquename()} // '',
        };
      }
    }
  } $gene_rs->all();

  return %ret_map;
}

func _safe_join($expr, $array)
{
  if (defined $array) {
    return join $expr, @{$array};
  } else {
    return '';
  }
}

method _get_qualifier($fc, $fc_props)
{
  my @qual_bits;

  if (defined $fc_props->{qualifier}) {
    @qual_bits = grep {
      $self->config()->{geneontology_qualifier_flags}->{$_};
    } @{$fc_props->{qualifier}};
  } else {
    @qual_bits = ();
  }

  if ($fc->is_not()) {
    push @qual_bits, "NOT"
  }

  join('|', @qual_bits);
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

method retrieve() {
  my $chado = $self->chado();

  my $db_name = $self->config()->{db_name_for_cv};

  my %feature_details = $self->_get_feature_details();
  my %cv_abbreviations = (biological_process => 'P',
                          cellular_component => 'C',
                          molecular_function => 'F',
                        );

  my $it = do {
    my $cv_rs =
      $chado->resultset('Cv::Cv')->search([
        map { { 'me.name' => $_ } } (@go_cv_names, $ext_cv_name)
      ]);

    my $cvterm_rs =
      $chado->resultset('Cv::Cvterm')->search({
        cv_id => { -in => $cv_rs->get_column('cv_id')->as_query() } }
                                            );
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
        my $cv_name = $cvterm->cv()->name();

        if (!grep { $_ eq $cv_name } @go_cv_names) {
          warn "skipping $cv_name\n";
          goto ROW;
        }

        my $feature = $row->feature();
        my $details = $feature_details{$feature->feature_id()};

        if (!defined $details) {
          warn "can't find details for: ", $feature->uniquename(), "\n";
          goto ROW;
        }

        if ($details->{type} ne 'gene') {
          warn "skipping: ", $details->{type}, "\n";
          warn $row->feature()->uniquename(), ' ', $row->cvterm()->name(), "\n";

          goto ROW;
        }

        my $qualifier = $self->_get_qualifier($row, \%row_fc_props);
        my $dbxref = $cvterm->dbxref();
        my $id = $dbxref->db()->name() . ':' . $dbxref->accession();
        my $evidence = _safe_join('|', $row_fc_props{evidence});
        if (!defined $evidence || length $evidence == 0) {
          warn "no evidence for $fc_id\n";
          goto ROW;
        }
        my $evidence_code = $self->{_evidence_to_code}->{$evidence};
        if (!defined $evidence_code) {
          warn q|can't find the evidence code for "$evidence"|;
          goto ROW;
        }
        my $with_from = _safe_join('|', $row_fc_props{with});
        my $aspect = $cv_abbreviations{$cv_name};
        my $pub = $row->pub();
        my $gene = $details->{gene} // die "no gene for ", $feature->uniquename();
        my $gene_uniquename = $gene->uniquename();
        my $gene_name = $gene->name() // $gene_uniquename;
        my $synonyms_ref = $details->{synonyms} // [];
        my $synonyms = join '|', @{$synonyms_ref};
        my $product = $details->{product} // '';
        my $taxon = 'taxon:' . $self->{_organism_taxonid};
        my $date = _safe_join('|', [map { _fix_date($_) } @{$row_fc_props{date}}]);
        my $gene_product_form_id = _safe_join('|', $row_fc_props{gene_product_form_id});
        return [$db_name, $gene_uniquename, $gene_name,
                $qualifier, $id, $pub->uniquename(),
                $evidence_code, $with_from, $aspect, $product, $synonyms,
                'gene', $taxon, $date, $db_name, $extensions // '',
                $gene_product_form_id];
      } else {
        return undef;
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
  return (join "\t", @$res) . "\n";
}
