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
use Carp;

use Moose;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::FeatureDumper';
with 'PomBase::Role::Embl::Located';
with 'PomBase::Role::Embl::SystematicID';

has embl_type => (is => 'ro',
                  isa => 'Str',
                  required => 1,
                 );
has so_type => (is => 'ro',
                isa => 'Maybe[Str]',
               );
has organism => (is => 'ro',
                 required => 1,
                 isa => 'Bio::Chado::Schema::Organism::Organism',
                );

has objs => (is => 'ro', isa => 'HashRef[Str]', default => sub { {} });

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

method BUILD
{
  my $chado = $self->chado();

  if (defined $self->so_type()) {
    my $so_cv = $chado->resultset('Cv::Cv')->find({ name => 'sequence' });

    $self->objs()->{so_cvterm} =
      $chado->resultset('Cv::Cvterm')->find({ name => $self->so_type(),
                                              cv_id => $so_cv->cv_id() });
  }
}

method process($feature, $delayed_features)
{
  my $feat_type = $feature->primary_tag();

  my $uniquename = $self->get_uniquename($feature);

  if ($feature_loader_conf{$feat_type}->{delay}) {
    $delayed_features->{$uniquename} = {
      feature => $feature,
    };

    return;
  }

  if ($feature_loader_conf{$feat_type}->{collected}) {
    push @{$delayed_features->{$uniquename}->{collected_features}}, $feature;
    return;
  }

  if ($self->embl_type() ne $feat_type) {
    croak ("wrong type of feature ($feat_type) passed to process() ",
           "which expects a ", $self->embl_type());
  }

  $self->store_location($feature);

  return $self->store_feature($feature, $uniquename);
}

method store_feature($feature, $uniquename)
{
  my $chado = $self->chado();

  my $name = undef;

  if ($feature->has_tag('gene')) {
    # XXX handle extra /genes as synonyms
    ($name) = $feature->get_tag_values('gene');
  }

  my %create_args = (
    type_id => $self->objs()->{so_cvterm}->cvterm_id(),
    uniquename => $uniquename,
    name => $name,
    organism_id => $self->organism()->organism_id(),
  );

  return $chado->resultset('Sequence::Feature')->create({%create_args});
}

1;
