package PomBase::Role::Embl::SystematicID;

=head1 NAME

PomBase::Role::Embl::SystematicID - Code for getting the systematic_id from
                                    an EMBL feature

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::Embl::SystematicID

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

use Moose::Role;

with 'PomBase::Role::FeatureDumper';

method get_uniquename($feature)
{
  state $type_seen = {};
  state $feature_cache = {};

  if ($feature->{chado_uniquename}) {
    return @{$feature->{chado_uniquename}};
  }

  my $embl_type = $feature->primary_tag();

  if (!$feature->has_tag("systematic_id")) {
    if ($embl_type eq 'CDS') {
      $self->dump_feature($feature);
      croak('CDS feature has no systematic_id');
    }

    my $loc = $feature->location();

    my $seq = $feature->entire_seq();
    my $seq_display_id = $seq->display_id();

    return $seq_display_id . '_' . $feature->primary_tag() .
      '_' . $loc->start() . '..' . $loc->end();
  }

  my @systematic_ids = $feature->get_tag_values("systematic_id");

  if (@systematic_ids > 1) {
    my $systematic_id_count = scalar(@systematic_ids);
    warn "  expected 1 systematic_id, got $systematic_id_count, for:";
    $self->dump_feature($feature);
    exit(1);
  }

  my $systematic_id = $systematic_ids[0];
  my $orig_systematic_id = $systematic_id;

  if (grep { $_ eq $embl_type } qw(intron 5'UTR 3'UTR)) {
    my $key = "$systematic_id.1:$embl_type";
    my $type_count = ++$type_seen->{$key};
    $systematic_id = "$key:$type_count";
  }

  $feature->{chado_uniquename} = [$systematic_id, $orig_systematic_id];

  return ($systematic_id, $orig_systematic_id);
}

1;
