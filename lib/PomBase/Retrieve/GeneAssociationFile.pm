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

use List::Gen 'iterate';

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Retriever';

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
    $evidence_to_code{$details->{name}} = $code;
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

func _get_base_term($cvterm)
{
  if ($cvterm->cv()->name() eq $ext_cv_name) {
    my @rels = $cvterm->cvterm_relationship_subjects();
    map {
      my $rel = $_;
      if ($rel->type()->name() eq 'is_a') {
        return $rel->object();
      };
    } @rels;
  }

  return $cvterm;
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
    search({ 'subject.organism_id' => $self->{_organism}->organism_id(),
             'type_2.name' => 'gene',
             'type.name' => 'part_of' },
           { join => [ 'subject', 'type', { object => 'type' } ],
             prefetch => [ 'subject', 'object', 'type' ] });

  map {
    my $rel = $_;
    my $object = $rel->object();
    my $type = $rel->type();
      print $rel->subject()->uniquename(), " ", $type->name(), " ", $rel->object()->uniquename(), "\n";
    if ($type->name() eq 'part_of') {
      if (defined $ret_map{$rel->subject_id()}->{gene}) {
        die "feature has two part_of parents";
      } else {
        $ret_map{$rel->subject_id()} = {
          gene => $object,
          synonyms => $synonyms{$object->feature_id()},
          product => $products{$object->uniquename()} // '',
        };
      }
    }
  } $gene_rs->all();

  return %ret_map;
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

    my $fc_props_rs = $feature_cvterm_rs->search_related('feature_cvtermprops')->
      search({}, { prefetch => [ 'type' ] });;

    while (defined (my $prop = $fc_props_rs->next())) {
      $fc_props{$prop->feature_cvterm_id()}->{$prop->type()->name()} = $prop->value();
    }

    my $results =
      $feature_cvterm_rs->search({},
        {
          prefetch => [ { cvterm => [ { dbxref => 'db' }, 'cv' ] }, 'feature', 'pub' ]
        },
      );

    iterate {
      my $row = $results->next();

      if (defined $row) {
        my %row_fc_props = %{$fc_props{$row->feature_cvterm_id()}};
        my $cvterm = $row->cvterm();
        my $cv_name = $cvterm->cv()->name();
        my $base_cvterm = _get_base_term($cvterm);
        my $base_cv_name = $base_cvterm->cv()->name();
        my $qualifier = 'QUALIFIER';
        my $dbxref = $base_cvterm->dbxref();
        my $id = $dbxref->db()->name() . ':' . $dbxref->accession();
        my $evidence = $row_fc_props{evidence};
        my $evidence_code = $self->{_evidence_to_code}->{$evidence}
          // die "can't find evidence code for $evidence\n";
        my $with_from = $row_fc_props{with} // '';
        my $aspect = $cv_abbreviations{$base_cv_name};
        my $pub = $row->pub();
        my $feature = $row->feature();
        my $details = $feature_details{$feature->feature_id()};
        my $gene = $details->{gene} // die "no gene for ", $feature->uniquename();
        my $gene_name = $gene->name() // '';
        my $synonyms_ref = $details->{synonyms} // [];
        my $synonyms = join '|', @{$synonyms_ref};
        my $product = $details->{product} // '';
        my $taxon = 'taxon:' . $self->{_organism_taxonid};
        my $date = $row_fc_props{date};
        my $annotation_extension = "ANNOTATION_EXTENSION";
        my $gene_product_form_id = $row_fc_props{gene_product_form_id} // '';
        return [$db_name, $feature->uniquename(), $gene_name,
                $qualifier, $id, $pub->uniquename(),
                $evidence,
                $evidence_code, $with_from, $aspect, $product, $synonyms,
                $base_cvterm->name(), $base_cv_name, 'gene', $taxon,
                $date, $db_name, $annotation_extension,
                $gene_product_form_id];
      } else {
        return undef;
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
