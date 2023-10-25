package PomBase::Importer;

=head1 NAME

PomBase::Importer - A retriever role

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Importer

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2023 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose::Role;

has reference_annotation_counts => (is => 'ro', init_arg => undef,
                                    isa => 'HashRef', default => sub { {} });

has reference_pub_objects => (is => 'ro', init_arg => undef,
                              isa => 'HashRef', default => sub { {} });

has json_encoder => (is => 'ro', init_arg => undef, lazy => 1,
                     builder => '_build_json_encoder');

has submitter_name => (is => 'rw');
has submitter_orcid => (is => 'rw');
has submitter_status => (is => 'rw');

requires 'create_pubprop';


sub _build_json_encoder {
  my $self = shift;

  return JSON->new()->pretty(0)->canonical(1);
}

sub record_pub_object {
  my $self = shift;
  my $reference = shift;
  my $pub = shift;

  $self->reference_pub_objects()->{$reference} = $pub;
}

sub increment_ref_annotation_count {
  my $self = shift;
  my $reference = shift;

  if (!exists $self->reference_annotation_counts()->{$reference}) {
    $self->reference_annotation_counts()->{$reference} = 0;
  }

  $self->reference_annotation_counts()->{$reference}++;
}

sub parse_submitter_line {
  my $self = shift;
  my $line = shift;

  if ($line =~ /^#submitter_(\w+):\s*(.*?)\s*$/i) {
    my $type = lc $1;
    my $value = $2;
    if ($type eq 'name') {
      $self->submitter_name($value);
    } else {
      if ($type eq 'orcid') {
        $self->submitter_orcid($value);
      } else {
        if ($type eq 'status') {
          $self->submitter_status($value);
        }
      }
    }
  }
}

sub store_annotation_file_curator {
  my $self = shift;
  my $file_name = shift;
  my $file_type = shift;

  if (defined $self->submitter_name() &&
      defined $self->submitter_orcid() &&
      defined $self->submitter_status()) {
    my $encoder = $self->json_encoder();

    while (my ($reference, $count) = each %{$self->reference_annotation_counts()}) {
      my %curator_details = (
        name => $self->submitter_name(),
        annotation_count => $count,
        file_name => $file_name,
        file_type => $file_type,
      );

      if ($self->submitter_orcid() !~ /^\s*$/) {
        $curator_details{orcid} = $self->submitter_orcid();
      }

      if (lc $self->submitter_status() eq 'community') {
        $curator_details{community_curator} = JSON::true;
      } else {
        $curator_details{community_curator} = JSON::false;
      }

      my $curator_json = $encoder->encode(\%curator_details);
      my $pub = $self->reference_pub_objects()->{$reference};
      $self->create_pubprop($pub, 'annotation_file_curator', $curator_json);
    }
  }
}

1;
