package PomBase::Chado::LoadFeat;

=head1 NAME

PomBase::Chado::LoadFeat - Code for loading a feature into Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::LoadFeat

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

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::FeatureDumper';
with 'PomBase::Role::Embl::SystematicID';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::CoordCalculator';

has embl_type => (is => 'ro',
                  isa => 'Str',
                  required => 1,
                 );
has so_type => (is => 'ro',
                isa => 'Maybe[Str]',
                required => 1,
               );
has organism => (is => 'ro',
                 required => 1,
                 isa => 'Bio::Chado::Schema::Organism::Organism',
                );

my %feature_loader_conf = (
  CDS => {
    delay => 1,
  },
  LTR => {
  },
  misc_RNA => {
  },
  "5'UTR" => {
    collected => 1,
  },
  "3'UTR" => {
    collected => 1,
  },
  "exon" => {
    collected => 1,
  },
  "intron" => {
    collected => 1,
  },
);

method process($feature, $chromosome, $delayed_features)
{
  my $feat_type = $feature->primary_tag();

  my $uniquename = $self->get_uniquename($feature);

  if ($feature_loader_conf{$feat_type}->{delay}) {
    $delayed_features->{$uniquename}->{feature} = $feature;
    $delayed_features->{$uniquename}->{so_type} = $self->so_type();
    push @{$delayed_features->{$uniquename}->{"5'UTR_features"}}, ();
    push @{$delayed_features->{$uniquename}->{"3'UTR_features"}}, ();
    return;
  }

  if ($feature_loader_conf{$feat_type}->{collected}) {
    push @{$delayed_features->{$uniquename}->{"${feat_type}_features"}}, $feature;
    return;
  }

  if ($self->embl_type() ne $feat_type) {
    croak ("wrong type of feature ($feat_type) passed to process() ",
           "which expects a ", $self->embl_type());
  }

  return $self->store_feature($feature, $chromosome, $self->so_type(),
                              [$self->coords_of_feature($feature)]);
}

1;
