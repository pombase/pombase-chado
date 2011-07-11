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

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::CvQuery';

func should($this, $that)
{
  if ($this ne $that) {
    my @call = caller(0);
    warn qq("$this" should be "$that" at $call[1] line $call[2].\n);
  }
}

method check
{
  my $chado = $self->chado();

  my $rel_rs = $chado->resultset('Sequence::FeatureRelationship');
  should ($rel_rs->count(), 52);

  my $loc_rs = $chado->resultset('Sequence::Featureloc');
  should ($loc_rs->count(), 64);

  my $feature_prop_rs = $chado->resultset('Sequence::Featureprop');
  should ($feature_prop_rs->count(), 10);

  my $feature_dbxref_rs = $chado->resultset('Sequence::FeatureDbxref');
  should ($feature_dbxref_rs->count(), 7);

  my $feature_synonym_rs = $chado->resultset('Sequence::FeatureSynonym');
  should ($feature_synonym_rs->count(), 2);

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
  should ($gene->feature_cvterms()->count(), 9);

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
  my $seq_feat_rs =
    $chado->resultset('Cv::Cvterm')->search({ cv_id => $seq_feat_cv->cv_id() });

  should ($seq_feat_rs->count(), 6);

  my $coiled_coil_cvterm = $self->get_cvterm('sequence_feature', 'coiled-coil');

  my @all_feature_cvterm = $chado->resultset('Sequence::FeatureCvterm')->all();
  should(scalar(@all_feature_cvterm), 96);

  my $feature_cvterm_rs =
    $transcript->feature_cvterms()->search({
      cvterm_id => $coiled_coil_cvterm->cvterm_id()
    });

  my $feature_cvterm = $feature_cvterm_rs->next();

  my @props = sort map { $_->value(); } $feature_cvterm->feature_cvtermprops();

  should ($props[0], '19700101');
  should ($props[1], 'predicted');
  should ($props[2], 'region');
  should(scalar(@props), 3);

  my @all_props = $chado->resultset('Sequence::FeatureCvtermprop')->all();
  should(scalar(@all_props), 133);

  my $feat_rs = $chado->resultset('Sequence::Feature');
  should ($feat_rs->count(), 71);

  for my $feat (sort { $a->uniquename() cmp $b->uniquename() } $feat_rs->all()) {
#    print $feat->uniquename(), " ", $feat->type()->name(), "\n";
  }

  my @pt_mod_cvterms =
    $chado->resultset('Cv::Cv')->find({ name => 'pt_mod' })
          ->search_related('cvterms')->all();
  should(scalar(@pt_mod_cvterms), 0);

  my @psi_mod_cvterms =
    $chado->resultset('Cv::Cv')->find({ name => 'PSI-MOD' })
          ->search_related('cvterms')->search_related('feature_cvterms')->all();
  should(scalar(@psi_mod_cvterms), 1);
}

