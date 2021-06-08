package PomBase::Role::GOAnnotationProperties;

=head1 NAME

PomBase::Role::GOAnnotationProperties - Code for querying config for GO
                                        annotation and evidence codes

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::GOAnnotationProperties

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose::Role;

with 'PomBase::Role::ConfigUser';

has throughput_type_hash => (is => 'ro', lazy => 1,
                             builder => '_build_throughput_type_hash');

sub _build_throughput_type_hash {
  my $self = shift;

  my $config = $self->config();

  my %type_hash = ();

  while (my ($code, $details) = each %{$config->{evidence_types}}) {
    $type_hash{$code} = $details->{throughput_type};
  }

  return \%type_hash;
}

sub annotation_throughput_type {
  my $self = shift;
  my $evidence_code = shift;

  return $self->throughput_type_hash()->{$evidence_code};
}

1;
