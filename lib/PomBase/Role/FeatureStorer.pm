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

has objs => (is => 'ro', isa => 'HashRef[Str]', default => sub { {} });

method store_feature($feature, $chromosome, $so_type, $loc_bits)
{
  my $chado = $self->chado();

  my $so_cv = $chado->resultset('Cv::Cv')->find({ name => 'sequence' });

  my $so_cvterm =
    $chado->resultset('Cv::Cvterm')->find({ name => $so_type,
                                            cv_id => $so_cv->cv_id() });

  my $uniquename = $self->get_uniquename($feature);

  warn "  storing $uniquename ($so_type)\n";

  my $name = undef;

  if ($feature->has_tag('gene')) {
    # XXX FIXME TODO handle extra /genes as synonyms
    ($name) = $feature->get_tag_values('gene');
  }

  my $complement = ($feature->location()->strand() == -1);

  if ($so_type eq 'gene') {
    $self->store_gene_location($feature, $chromosome, $complement, $loc_bits);
  } else {
    my $start = $feature->location()->start();
    my $end = $feature->location()->end();
    $self->store_location($feature, $chromosome, $complement, $start, $end);
  }

  my %create_args = (
    type_id => $so_cvterm->cvterm_id(),
    uniquename => $uniquename,
    name => $name,
    organism_id => $self->organism()->organism_id(),
  );

  return $chado->resultset('Sequence::Feature')->create({%create_args});
}

1;
