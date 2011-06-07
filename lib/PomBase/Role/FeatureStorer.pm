package PomBase::Role::FeatureStorer;

=head1 NAME

PomBase::Role::FeatureStorer - Code for storing features in Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::FeatureStorer

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose::Role;

with 'PomBase::Role::Embl::StoreLocation';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::ChadoObj';

method store_feature($uniquename, $name, $synonyms, $so_type)
{
  my $so_cvterm = $self->get_cvterm('sequence', $so_type);

  print "  storing $uniquename ($so_type)\n";

  my %create_args = (
    type_id => $so_cvterm->cvterm_id(),
    uniquename => $uniquename,
    name => $name,
    organism_id => $self->organism()->organism_id(),
  );

  my $feature_rs = $self->chado()->resultset('Sequence::Feature');

  return $feature_rs->create({ %create_args });
}

method find_or_create_synonym($synonym_name, $type_name)
{
  my $type = $self->get_cvterm('PomBase synonym types', $type_name);

  return $self->chado()->resultset('Sequence::Synonym')->find_or_create({
    name => $synonym_name,
    synonym_sgml => $synonym_name,
    type_id => $type->cvterm_id(),
  });
}

method store_feature_synonym($feature, $synonym_name)
{
  my $synonym = $self->find_or_create_synonym($synonym_name, 'synonym');

  my $pub = $self->objs()->{null_pub};

  return $self->chado()->resultset('Sequence::FeatureSynonym')->find_or_create({
    feature_id => $feature->feature_id(),
    synonym_id => $synonym->synonym_id(),
    pub_id => $pub->pub_id(),
  });
}

method store_feature_and_loc($feature, $chromosome, $so_type,
                             $start_arg, $end_arg)
{
  my $chado = $self->chado();

  my $name = undef;
  my @synonyms = ();
  my ($uniquename) = $self->get_uniquename($feature, $so_type);

  if ($feature->has_tag('pseudo')) {
    $so_type = 'pseudogene';
  }

  my $chado_feature = $self->store_feature($uniquename, $name, [], $so_type);

  my $start = $start_arg // $feature->location()->start();
  my $end = $end_arg // $feature->location()->end();
  my $strand = $feature->location()->strand();

  $self->store_location($chado_feature, $chromosome, $strand, $start, $end);

  if ($feature->has_tag('gene')) {
    ($name, @synonyms) = $feature->get_tag_values('gene');

    for my $synonym (@synonyms) {
      $self->store_feature_synonym($chado_feature, $synonym);
    }
  }

  return $chado_feature;
}

method store_featureprop($feature, $type_name, $value)
{
  state $ranks = {};

  my $rank;

  if (exists $ranks->{$feature->feature_id()}->{$type_name}) {
    $rank = $ranks->{$feature->feature_id()}->{$type_name}++;
  } else {
    $ranks->{$feature->feature_id()}->{$type_name} = 1;
    $rank = 0;
  }

  my $type_cvterm = $self->get_cvterm('PomBase feature property types',
                                      $type_name);

  $self->chado()->resultset('Sequence::Featureprop')->create({
    feature_id => $feature->feature_id(),
    type_id => $type_cvterm->cvterm_id(),
    value => $value,
    rank => $rank,
  });
}

1;
