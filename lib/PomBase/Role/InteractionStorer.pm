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

requires 'store_featureprop';
requires 'store_feature_rel_pub';
requires 'store_feature_rel';
requires 'config';
requires 'get_feature_relationship';

has genetic_interaction_type => (is => 'ro', init_arg => undef,
                                 lazy => 1,
                                 builder => '_build_genetic_interaction');
has physical_interaction_type => (is => 'ro', init_arg => undef,
                                  lazy => 1,
                                  builder => '_build_physical_interaction');


method _build_genetic_interaction() {
  return $self->get_cvterm('PomBase interaction types', 'genetic_interaction');
}

method _build_physical_interaction() {
  return $self->get_cvterm('PomBase interaction types', 'physical_interaction');
}


method _find_metagenotypes($genotype_a, $genotype_b, $type, $organism, $pub, $evidence_type) {
  state $cache = {};

  my $key = $genotype_a->feature_id() . '-' .$genotype_b->feature_id() . '-' . $type->name();

  my $where = "me.feature_id IN (
SELECT metagenotype.feature_id
FROM feature metagenotype
JOIN feature_pub on metagenotype.feature_id = feature_pub.feature_id
JOIN feature_relationship genotype_a_part_of ON genotype_a_part_of.object_id = metagenotype.feature_id
JOIN feature genotype_a ON genotype_a.feature_id = genotype_a_part_of.subject_id
JOIN cvterm genotype_a_type ON genotype_a.type_id = genotype_a_type.cvterm_id
JOIN feature_relationship genotype_b_part_of ON genotype_b_part_of.object_id = metagenotype.feature_id
JOIN feature genotype_b ON genotype_b.feature_id = genotype_b_part_of.subject_id
JOIN cvterm genotype_b_type ON genotype_b.type_id = genotype_b_type.cvterm_id
WHERE metagenotype.type_id = ?
AND genotype_a_type.name = 'genotype'
AND genotype_b_type.name = 'genotype'
AND feature_pub.pub_id = ?)";

  if (!defined $cache->{$key}) {
    my $rs = $self->chado()->resultset('Sequence::Feature')
      ->search({ type_id => $type->cvterm_id(),
                 organism_id => $organism->organism_id(),
               },
               {
                 where => \$where,
                 bind => [$type->cvterm_id(), $pub->pub_id()],
               });

    my @filtered_features = grep {
      my $metagenotype = $_;

      my @props = $metagenotype->featureprops()->search({}, { prefetch => 'type' });

      grep {
        my $prop = $_;
        $prop->type()->name() eq 'evidence' && $prop->value() eq $evidence_type;
      } @props;
    } $rs->all();

    $cache->{$key} = \@filtered_features;
  }

  return @{$cache->{$key} // []};
}

=head2 store_interaction

 Usage   : $self->store_interaction(%args);
 Function:
 Args    :
  genotype_a - a Sequence::Feature with type "genotype"
  genotype_b - a Sequence::Feature with type "genotype"
  interaction_type_name - 'physical_interaction' or 'genetic_interaction'
  evidence_type - an evidence type eg. "Synthetic Lethality"
  source_db - eg. "PomBase"
  pub - a Pub object
  creation_date
  curator - { name => '...', email => '...' }
  approver_email
  first_approved_timestamp
  approved_timestamp
  canto_session
  notes - list of strings

 Return  : a list of the FeatureRelationship object that were created

=cut

method store_interaction_feature() {
  my %args = @_;
  my $genotype_a = $args{genotype_a};
  my $genotype_b = $args{genotype_b};
  my $rel_type_name = $args{rel_type_name};
  my $evidence_type = $args{evidence_type};
  my $source_db = $args{source_db};
  my $pub = $args{publication};
  my $creation_date = $args{creation_date};
  my $curator = $args{curator};
  my $approver_email = $args{approver_email};
  my $first_approved_timestamp = $args{first_approved_timestamp};
  my $approved_timestamp = $args{approved_timestamp};
  my $canto_session = $args{canto_session};
  my $annotation_throughput_type = $args{annotation_throughput_type};
  my $annotation_date = $args{annotation_date};
  my $notes = $args{notes} // [];
  my @notes = @$notes;

  state $feature_count = {};

  if (!exists $feature_count->{$canto_session}) {
    $feature_count->{$canto_session} //= 0;
  }

  $feature_count->{$canto_session}++;

  my $rel_type;

  if ($rel_type_name eq 'interacts_genetically' or
      $rel_type_name eq 'genetic_interaction') {
    $rel_type = $self->genetic_interaction_type();
  } else {
    if ($rel_type_name eq 'interacts_physically' or
        $rel_type_name eq 'physical_interaction') {
      $rel_type = $self->physical_interaction_type();
    } else {
      croak qq(unknown interaction type $rel_type_name\n);
    }
  }

  my $metagenotype_uniquename =
    $canto_session . "-$rel_type_name-metagenotype-" . $feature_count->{$canto_session};

  my $interaction = $self->store_metagenotype($metagenotype_uniquename, $rel_type,
                                              $genotype_a->organism(), $genotype_a,
                                              $genotype_b);

  $self->create_feature_pub($interaction, $pub);
  $self->store_featureprop($interaction, evidence => $evidence_type);

  $self->store_featureprop($interaction, source_database => $source_db);
  if (defined $creation_date) {
    $self->store_featureprop($interaction, date => $creation_date);
  }

  if (defined $curator) {
    $self->store_featureprop($interaction, curator_name => $curator->{name});
    $self->store_featureprop($interaction, curator_email => $curator->{email});

    $self->store_featureprop($interaction, community_curated =>
                               $curator->{community_curated} ? 'true' : 'false');
  }
  if (defined $first_approved_timestamp) {
    $self->store_featureprop($interaction, first_approved_timestamp => $first_approved_timestamp);
  }
  if (defined $approved_timestamp) {
    $self->store_featureprop($interaction, approved_timestamp => $approved_timestamp);
  }
  if (defined $approver_email) {
    $self->store_featureprop($interaction, approver_email => $approver_email);
  }
  if (defined $canto_session) {
    $self->store_featureprop($interaction, canto_session => $canto_session);
  }
  if (defined $annotation_throughput_type) {
    $self->store_featureprop($interaction, annotation_throughput_type => $annotation_throughput_type);
  }
  if (@notes) {
    for my $note (@notes) {
      $self->store_featureprop($interaction, interaction_note => $note);
    }
  }

  return $interaction;
}

1;
