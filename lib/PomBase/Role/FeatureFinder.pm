package PomBase::Role::FeatureFinder;

=head1 NAME

PomBase::Role::FeatureFinder - Code for looking up features in Chado.

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::FeatureFinder

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

with 'PomBase::Role::ChadoUser';

method find_chado_feature ($systematic_id, $try_name, $ignore_case, $organism) {
   my $rs = $self->chado()->resultset('Sequence::Feature');

   state $cache = {};

   my $cache_key = "$systematic_id $try_name $ignore_case";

   if (exists $cache->{$cache_key}) {
     return $cache->{$cache_key};
   }
   if (defined $organism) {
     $rs = $rs->search({ organism_id => $organism->organism_id() });
   }

   my $feature;

   if ($ignore_case) {
     my @results = $rs->search(\[ "LOWER(uniquename) = ?",
                               [ plain_value => lc $systematic_id ]])->all();
     if (@results > 1) {
       die "too many matches for $systematic_id\n";
     } else {
       $feature = $results[0];
     }
   } else {
     $feature = $rs->find({ uniquename => $systematic_id });
   }

   if (defined $feature) {
     $cache->{$cache_key} = $feature;
     return $feature;
   }

   if ($try_name) {
     if ($ignore_case) {
       my @results = $rs->search(\[ "LOWER(name) = ?",
                                 [ plain_value => lc $systematic_id ]])->all();
       if (@results > 1) {
         die "too many matches for $systematic_id\n";
       } else {
         $feature = $results[0];
       }
     } else {
       $feature = $rs->find({ name => $systematic_id });
     }

     if (defined $feature) {
       $cache->{$cache_key} = $feature;
       return $feature
     }
   }

   die "can't find feature for: $systematic_id\n";
 }

1;
