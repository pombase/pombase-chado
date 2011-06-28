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

use Carp::Assert;

with 'PomBase::Role::Embl::StoreLocation';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::ChadoObj';

method store_feature($uniquename, $name, $synonyms, $so_type)
{
  my $so_cvterm = $self->get_cvterm('sequence', $so_type);

  warn "  storing $uniquename/", ($name ? $name : 'no_name'),
    " ($so_type)" if $self->verbose();

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
  my $type = $self->get_cvterm('synonym_type', $type_name);

  if (!defined $type) {
    die "no synonym type cvterm found for $type_name\n";
  }

  return $self->chado()->resultset('Sequence::Synonym')->find_or_create({
    name => $synonym_name,
    synonym_sgml => $synonym_name,
    type_id => $type->cvterm_id(),
  });
}

method store_feature_synonym($feature, $synonym_name, $is_current)
{
  $is_current //= 1;

  my $synonym = $self->find_or_create_synonym($synonym_name, 'exact');

  my $pub = $self->objs()->{null_pub};

  return $self->chado()->resultset('Sequence::FeatureSynonym')->find_or_create({
    feature_id => $feature->feature_id(),
    synonym_id => $synonym->synonym_id(),
    pub_id => $pub->pub_id(),
    is_current => $is_current,
  });
}

method store_feature_and_loc($feature, $chromosome, $so_type,
                             $start_arg, $end_arg)
{
  my $chado = $self->chado();

  my ($uniquename, $transcript_uniquename, $gene_uniquename) =
    $self->get_uniquename($feature, $so_type);

  if ($so_type eq 'gene') {
    $uniquename = $gene_uniquename;
  }

  my $name = undef;

  if ($feature->has_tag('primary_name')) {
    my @primary_names = $feature->get_tag_values('primary_name');

    if (@primary_names > 1) {
      warn "$uniquename has more than one /primary_name\n";
    }

    $name = $primary_names[0];
  } else {
    if ($feature->has_tag('reserved_name')) {
      my @reserved_names = $feature->get_tag_values('reserved_name');

      if (@reserved_names > 1) {
        warn "$uniquename has more than one /reserved_name\n";
      }

      $name = $reserved_names[0];
    } else {
      if ($so_type eq 'gene') {
        warn "no /primary_name qualifier for $uniquename\n" if $self->verbose();
      }
    }
  }

  my @synonyms = ();

  if ($feature->has_tag('synonym')) {
    @synonyms = $feature->get_tag_values('synonym');
  }

  if ($feature->has_tag('pseudo')) {
    $so_type = 'pseudogene';
  }

  my $chado_feature = $self->store_feature($uniquename, $name, [], $so_type);

  my $start = $start_arg // $feature->location()->start();
  my $end = $end_arg // $feature->location()->end();
  my $strand = $feature->location()->strand();

  $self->store_location($chado_feature, $chromosome, $strand, $start, $end);

  for my $synonym (@synonyms) {
    next if $synonym eq $uniquename;
    next if $synonym eq $gene_uniquename;
    next if defined $name and $synonym eq $name;

    $self->store_feature_synonym($chado_feature, $synonym);
  }

  if ($feature->has_tag('obsolete_name')) {
    my @obsolete_names = $feature->get_tag_values('obsolete_name');
    if (@obsolete_names > 1) {
      warn "$uniquename has more than one /obsolete_name\n";
    }
    $self->store_feature_synonym($chado_feature, $obsolete_names[0], 0);
  }

  return $chado_feature;
}

method store_featureprop($feature, $type_name, $value)
{
  state $ranks = {};

  assert (defined $value);

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
