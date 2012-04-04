package PomBase::Role::InteractionStorer;

=head1 NAME

PomBase::Role::InteractionStorer - Store interactions in Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::InteractionStorer

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose::Role;

requires 'store_feature_relationshipprop';
requires 'store_feature_rel_pub';
requires 'store_feature_rel';

has genetic_interaction_type => (is => 'ro', init_arg => undef,
                                 lazy => 1,
                                 builder => '_build_genetic_interaction');
has physical_interaction_type => (is => 'ro', init_arg => undef,
                                  lazy => 1,
                                  builder => '_build_physical_interaction');


method _build_genetic_interaction()
{
  return $self->get_cvterm('PomBase interaction types', 'interacts_genetically');
}

method _build_physical_interaction()
{
  return $self->get_cvterm('PomBase interaction types', 'interacts_physically');
}

method store_interaction()
{
  my %args = @_;
  my $feature_a = $args{feature_a};
  my $feature_b = $args{feature_b};
  my $rel_type_name = $args{rel_type_name};
  my $evidence_type = $args{evidence_type};
  my $source_db = $args{source_db};
  my $pub = $args{pub};
  my $creation_date = $args{creation_date};

  my $rel_type;

  if ($rel_type_name eq 'genetic_interaction') {
    $rel_type = $self->genetic_interaction_type();
  } else {
    if ($rel_type_name eq 'physical_interaction') {
      $rel_type = $self->physical_interaction_type();
    } else {
      croak qq(unknown interaction type $rel_type_name\n);
    }
  }

  my $rel = $self->store_feature_rel($feature_a, $feature_b, $rel_type);

  $self->store_feature_relationshipprop($rel, evidence => $evidence_type);
  $self->store_feature_relationshipprop($rel, source_database => $source_db);
  $self->store_feature_relationshipprop($rel, date => $source_db);
  $self->store_feature_rel_pub($rel, $pub);
}

1;
