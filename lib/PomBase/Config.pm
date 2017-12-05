package PomBase::Config;

=head1 NAME

PomBase::Config - Configuration for a PomBase Chado load

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Config

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

use YAML qw(LoadFile);

has file_name => (is => 'ro');
has hash => (is => 'ro');

method BUILD {
  my %new_data;

  if (defined $self->file_name()) {
    my $load_config = LoadFile($self->file_name());

    if (!defined $load_config) {
      die "failed to read any configuration from: ", $self->file_name(),
        " - is the file empty?\n";
    }

    %new_data = %$load_config;
  } else {
    if (defined $self->hash()) {
      %new_data = %{$self->hash()};
    } else {
      die "Config constructor needs a file_name or hash parameter\n";
    }
  }

  for my $key (keys %new_data) {
    $self->{$key} = $new_data{$key};
  }

  # add a lowercase version of each evidence code
  for my $code (keys %{$self->{evidence_types}}) {
    my $details = $self->{evidence_types}->{$code};
    if (defined $details) {
      $self->{evidence_types}->{lc $details->{name}} //= $details;
    } else {
      $details = { name => $code };
      $self->{evidence_types}->{$code} = $details;
    }
    my $ev_name = $details->{name};
    (my $short_name = $ev_name) =~ s/\s+evidence$//;
    $self->{evidence_name_to_code}->{$ev_name} = $code;
    $self->{evidence_name_to_code}->{lc $ev_name} = $code;
    $self->{evidence_name_to_code}->{$short_name} = $code;
    $self->{evidence_name_to_code}->{lc $short_name} = $code;
    $self->{evidence_types}->{lc $code} = $details;
    $self->{evidence_types}->{lc $code} = $details;
    $self->{evidence_types}->{$short_name . ' evidence'} = $details;
    $self->{evidence_types}->{lc $short_name . ' evidence'} = $details;
    $self->{evidence_types}->{$short_name} = $details;
    $self->{evidence_types}->{lc $short_name} = $details;
  }
}

1;
