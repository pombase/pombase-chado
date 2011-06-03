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

method store_feature_and_loc($feature, $chromosome, $so_type,
                             $start_arg, $end_arg)
{
  my $chado = $self->chado();

  my $name = undef;

  my @synonyms = ();

  if ($feature->has_tag('gene')) {
    # XXX FIXME TODO handle extra /genes as synonyms
    ($name, @synonyms) = $feature->get_tag_values('gene');
  }

  my ($uniquename) = $self->get_uniquename($feature);

  my $chado_feature = $self->store_feature($uniquename, $name, [], $so_type);

  my $start = $start_arg // $feature->location()->start();
  my $end = $end_arg // $feature->location()->end();
  my $strand = $feature->location()->strand();

  $self->store_location($chado_feature, $chromosome, $strand, $start, $end);

  return $chado_feature;
}

1;
