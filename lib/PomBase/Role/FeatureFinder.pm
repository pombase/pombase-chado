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


=head2 find_chado_feature

 Usage   : my $feature = $some_object->find_chado_feature($identifier);
 Function: Return a Sequence::Feature object from Chado
 Args    : $identifier    - the uniquename of the feature to find (required)
           $try_name      - if true, try the feature name as well as the
                            uniquename (optional, default: false)
           $ignore_case   - if true match case insensitively (optional,
                            default: false)
           $organism      - if defined search for feature only from this organism
                            (optional)
           $feature_types - an array ref of feature types to search eg.
                            ['pseudogene', 'gene']  (optional, default: all types)

 Return  :

=cut

method find_chado_feature ($systematic_id, $try_name, $ignore_case, $organism, $feature_types) {
   my $rs = $self->chado()->resultset('Sequence::Feature');

   state $cache = {};

   $try_name //= 0;
   $ignore_case //= 0;
   my $organism_fullname = '';
   if (defined $organism) {
     $organism_fullname = $organism->genus() . '_' . $organism->species();
   }

   if (!defined $systematic_id) {
     croak "no systematic_id passed to find_chado_feature()";
   }

   my $cache_key = "$systematic_id $try_name $ignore_case $organism_fullname " .
     join ('+', @{$feature_types // []});

   if (exists $cache->{$cache_key}) {
     return $cache->{$cache_key};
   }
   if (defined $organism) {
     $rs = $rs->search({ organism_id => $organism->organism_id() });
   }

   if (defined $feature_types) {
     $rs = $rs->search({ 'type.name' => { -in => $feature_types } },
                       { join => 'type' });
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
       my @results = $rs->search(\[ "LOWER(me.name) = ?",
                                 [ plain_value => lc $systematic_id ]])->all();
       if (@results > 1) {
         die "too many matches for $systematic_id\n";
       } else {
         $feature = $results[0];
       }
     } else {
       $feature = $rs->find({ 'me.name' => $systematic_id });
     }

     if (defined $feature) {
       $cache->{$cache_key} = $feature;
       return $feature
     }
   }

   die "can't find feature for: $systematic_id\n";
 }

1;
