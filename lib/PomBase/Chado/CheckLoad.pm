package PomBase::Chado::CheckLoad;

=head1 NAME

PomBase::Chado::CheckLoad - Check that the loading worked

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::CheckLoad

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

use Carp::Assert qw(assert);

use Data::Compare;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::FeatureFinder';

has verbose => (is => 'ro');

func should($this, $that)
{
  if (!defined $this) {
    carp "first arg not defined in call to should()";
    return;
  }
  if (!defined $that) {
    carp "second arg not defined in call to should()";
    return;
  }
  if ($this ne $that) {
    my @call = caller(0);
    warn qq("$this" should be "$that" at $call[1] line $call[2].\n);
  }
}

method check
{
  my $chado = $self->chado();

  warn "checking results ...\n";

  my $rel_rs = $chado->resultset('Sequence::FeatureRelationship');
  should ($rel_rs->count(), 55);

  my $relprop_rs = $chado->resultset('Sequence::FeatureRelationshipprop');
  should ($relprop_rs->count(), 9);

  my $loc_rs = $chado->resultset('Sequence::Featureloc');
  should ($loc_rs->count(), 65);

  my $feature_prop_rs = $chado->resultset('Sequence::Featureprop');
  should ($feature_prop_rs->count(), 13);

  my $feature_dbxref_rs = $chado->resultset('Sequence::FeatureDbxref');
  should ($feature_dbxref_rs->count(), 29);

  my $feature_synonym_rs = $chado->resultset('Sequence::FeatureSynonym');
  should ($feature_synonym_rs->count(), 3);

  my $db_res = $chado->resultset('General::Db');
  assert($db_res->search({ name => 'warning' })->count() == 0);

  my $pombe = $chado->resultset('Organism::Organism')
    ->find({ species => 'pombe' });

  my $gene_cvterm = $self->get_cvterm('sequence', 'gene');

  my $gene_rs = $chado->resultset('Sequence::Feature')
    ->search({
      type_id => $gene_cvterm->cvterm_id(),
      organism_id => $pombe->organism_id(),
    }, { order_by => 'uniquename' });

  should ($gene_rs->count(), 10);

  my $gene = $gene_rs->search({ uniquename => 'SPAC1556.06' })->next();

  should ($gene->uniquename(), "SPAC1556.06");
  should ($gene->feature_cvterms()->count(), 11);

  my $transcript = $chado->resultset('Sequence::Feature')
          ->find({ uniquename => 'SPAC977.10.1'});
  my $cvterms_rs =
    $transcript->feature_cvterms()->search_related('cvterm');
  assert (grep { $_->name() eq 'plasma membrane' } $cvterms_rs->all());

  my $product_cv = $chado->resultset('Cv::Cv')
    ->find({ name => 'PomBase gene products' });

  for my $cvterm ($chado->resultset('Cv::Cvterm')->search({
    cv_id => $product_cv->cv_id()
  })->all()) {
#    print $cvterm->name(), "\n";
  }

  my $seq_feat_cv = $self->get_cv('sequence_feature');
  assert (!defined $seq_feat_cv);

  my $coiled_coil_cvterm = $self->get_cvterm('sequence', 'coiled_coil');

  my @all_feature_cvterm = $chado->resultset('Sequence::FeatureCvterm')->all();
  should(scalar(@all_feature_cvterm), 112);

  my $cvterm_property_type_cv =
    $chado->resultset('Cv::Cv')->find({ name => 'cvterm_property_type' });
  my $cvtermprop_types_rs = $chado->resultset('Cv::Cvterm')->search({ cv_id => $cvterm_property_type_cv->cv_id(),
                                                                      name => { like => 'annotation_extension_relation-%' } });

  my $an_ex_rel_props_rs = $chado->resultset('Cv::Cvtermprop')->search({
    type_id => { -in => $cvtermprop_types_rs->get_column('cvterm_id')->as_query() } });
  should($an_ex_rel_props_rs->count(), 4);

  my ($localizes_term) = grep { $_->cvterm()->name() =~ /cellular protein localization \[localizes\] SPAC167.03c/ } @all_feature_cvterm;
  assert(defined $localizes_term);

  should($localizes_term->feature_cvtermprops()->count(), 4);

  my $feature_cvterm_rs =
    $transcript->feature_cvterms()->search({
      cvterm_id => $coiled_coil_cvterm->cvterm_id()
    });

  my $feature_cvterm = $feature_cvterm_rs->next();

  {
    my @actual_props = map { ( $_->type()->name(), $_->value() ) } $feature_cvterm->feature_cvtermprops();

    my @expected_props = ( 'qualifier', 'predicted', 'qualifier',
                           'region', 'evidence', 'Inferred from Direct Assay',
                           'date', '19700101');

    assert(Compare(\@expected_props, \@actual_props));
  }

  my @all_props = $chado->resultset('Sequence::FeatureCvtermprop')->all();
  should(scalar(@all_props), 228);

  my $feat_rs = $chado->resultset('Sequence::Feature');
  should ($feat_rs->count(), 72);

  for my $feat (sort { $a->uniquename() cmp $b->uniquename() } $feat_rs->all()) {
#    print $feat->uniquename(), " ", $feat->type()->name(), "\n";
  }

  assert(!defined $chado->resultset('Cv::Cv')->find({ name => 'pt_mod' }));

  assert($chado->resultset('Cv::Cv')->find({ name => 'PSI-MOD' })
               ->search_related('cvterms')->count() > 10);

  my @psi_mod_cvterms =
    $chado->resultset('Cv::Cv')->find({ name => 'PSI-MOD' })
          ->search_related('cvterms')->search_related('feature_cvterms')->all();
  should(scalar(@psi_mod_cvterms), 1);

  my $intron_cvterm = $self->get_cvterm('sequence', 'intron');

  my $intron_rs =
    $chado->resultset('Sequence::Feature')
      ->search({ type_id => $intron_cvterm->cvterm_id() });

  should($intron_rs->count(), 4);
  should($intron_rs->search({ name => { '!=', undef }})->count(), 0);

  my $orthologous_to_cvterm = $self->get_cvterm('sequence', 'orthologous_to');

  my $orth_rel_rs =
    $chado->resultset('Sequence::FeatureRelationship')
          ->search({ type_id => $orthologous_to_cvterm->cvterm_id() });

  should($orth_rel_rs->count(), 4);

  my $spac977_12_1 = 'SPAC977.12.1';

  my $so_ann_ex_gene =
    $chado->resultset('Sequence::Feature')->find({ uniquename => $spac977_12_1 });

  my @so_ann_ex_go_terms =
    $so_ann_ex_gene->feature_cvterms()->search_related('cvterm');

  # check for annotation extension with a SO term
  warn "cvterms for $spac977_12_1:\n" if $self->verbose();
  assert (grep {
    warn '  props for ', $_->name(), ":\n" if $self->verbose();
    for my $prop ($_->cvtermprops()) {
      warn '    ', $prop->type()->name(), ' => ', $prop->value(), "\n" if $self->verbose();
    }
    $_->name() eq 'chromosome, centromeric region [dependent_on] protein binding (^has_substrate(GeneDB_Spombe:SPCC594.07c)) [requires_feature] regional_centromere_central_core';
  } @so_ann_ex_go_terms);

  my $spbc409_20c_1 = 'SPBC409.20c.1';

  my $ann_ex_gene =
    $chado->resultset('Sequence::Feature')->find({ uniquename => $spbc409_20c_1 });

  my @ann_ex_go_terms =
    $ann_ex_gene->feature_cvterms()->search_related('cvterm');

  should(scalar(@ann_ex_go_terms), 8);

  # check for annotation extension targeting genes
  warn "cvterms for $spbc409_20c_1:\n" if $self->verbose();
  my ($methyltransferase_activity_term) = grep {
    warn '  ', $_->name(), "\n" if $self->verbose();
    for my $prop ($_->cvtermprops()) {
      warn '    ', $prop->type()->name(), ' => ', $prop->value(), "\n" if $self->verbose();
    }
    $_->name() eq 'protein-lysine N-methyltransferase activity [has_downstream_target] SPAC977.10';
  } @ann_ex_go_terms;

  {
    my $fcs = $methyltransferase_activity_term->feature_cvterms();
    my @actual_props = map { ( $_->type()->name(), $_->value() ) } $fcs->first()->feature_cvtermprops();

    my @expected_props = ( 'assigned_by', 'PomBase',
                           'evidence', 'Inferred from Mutant Phenotype',
                           'date', '20050510', );

    should(scalar(@expected_props), scalar(@actual_props));

    assert(Compare(\@expected_props, \@actual_props));
  }

  # check for IGI converted to annotation extension
  assert (grep {
    warn '  ', $_->name(), "\n" if $self->verbose();
    for my $prop ($_->cvtermprops()) {
      warn '    ', $prop->type()->name(), ' => ', $prop->value(), "\n" if $self->verbose();
    }
    $_->name() eq 'cellular protein localization [localizes] SPAC167.03c';
  } @ann_ex_go_terms);

  # check for ISS convert to ISO when with=SGD
  my @spbc409_20c_1_fcs = $ann_ex_gene->feature_cvterms();
  warn "check for ISS -> ISO for $spbc409_20c_1:\n" if $self->verbose();
  my ($binding_fc) = grep {
    warn '  ', $_->cvterm()->name(), "\n" if $self->verbose();
    for my $prop ($_->feature_cvtermprops()) {
      warn '    ', $prop->type()->name(), ' => ', $prop->value(), "\n" if $self->verbose();
    }
    $_->cvterm()->name() eq "mRNA 3'-UTR binding";
  } @spbc409_20c_1_fcs;

  my @actual_props = map { ( $_->type()->name(), $_->value() ) } $binding_fc->feature_cvtermprops();

  my @expected_props = ( 'assigned_by', 'PomBase',
                         'with', 'SGD:S000002371',
                         'evidence', 'Inferred from Sequence Orthology',
                         'date', '20050322', );

  assert(scalar(@expected_props) == scalar(@actual_props));

  assert(Compare(\@expected_props, \@actual_props));
}
