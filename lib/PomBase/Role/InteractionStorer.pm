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

use strict;
use warnings;
use Carp;

use Moose::Role;

requires 'store_feature_relationshipprop';
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


has symmetrical_interaction_evidence_codes => (is => 'rw', init_arg => undef,
                                               lazy_build => 1);

sub _build_genetic_interaction {
  my $self = shift;

  return $self->get_cvterm('PomBase interaction types', 'interacts_genetically');
}

sub _build_physical_interaction {
  my $self = shift;

  return $self->get_cvterm('PomBase interaction types', 'interacts_physically');
}

sub _build_symmetrical_interaction_evidence_codes {
  my $self = shift;

  my @symmetrical_ev_codes = ();

  my %evidence_types = %{$self->config()->{evidence_types}};

  map {
    my $ev_name = $_;

    my $symmetrical = $evidence_types{$ev_name}->{symmetrical};

    if ($symmetrical && lc $symmetrical ne 'no') {
      push @symmetrical_ev_codes, $ev_name;
    }
  } keys %evidence_types;

  return [@symmetrical_ev_codes];
}

sub _store_interaction_helper {
  my $self = shift;

  my %args = @_;
  my $feature_a = $args{feature_a};
  my $feature_b = $args{feature_b};
  my $rel_type_name = $args{rel_type_name};
  my $evidence_type = $args{evidence_type};
  my $source_db = $args{source_db};
  my $pub = $args{pub};
  my $creation_date = $args{creation_date};
  my $curator = $args{curator};
  my $approver_email = $args{approver_email};
  my $first_approved_timestamp = $args{first_approved_timestamp};
  my $approved_timestamp = $args{approved_timestamp};
  my $canto_session = $args{canto_session};
  my $annotation_throughput_type = $args{annotation_throughput_type};
  my $annotation_date = $args{annotation_date};
  my $notes = $args{notes} // [];
  my $is_inferred = $args{is_inferred};
  my @notes = @$notes;

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

  my @existing_interactions =
    $self->get_feature_relationship($feature_a, $feature_b, $pub, $evidence_type);

  if (@existing_interactions > 1) {
    die "more than one existing interaction for ", $feature_a->uniquename(),
      " <- ", $evidence_type, " -> ", $feature_b->uniquename(), "  from ",
      $pub->uniquename();
  }

  my $rel;

  my $existing_rel = undef;

  if (@existing_interactions == 1) {
    $rel = $existing_interactions[0];
    $existing_rel = $rel;
  } else {
    $rel = $self->store_feature_rel($feature_a, $feature_b, $rel_type);
    $self->store_feature_rel_pub($rel, $pub);
    $self->store_feature_relationshipprop($rel, evidence => $evidence_type);
  }

  if (!$existing_rel) {
    # only store for new interactions
    $self->store_feature_relationshipprop($rel, source_database => $source_db);
    if (defined $creation_date) {
      $self->store_feature_relationshipprop($rel, date => $creation_date);
    }
    $self->store_feature_relationshipprop($rel, is_inferred => ($is_inferred ? 'yes' : 'no'));
  }

  if (defined $curator) {
    $self->store_feature_relationshipprop($rel, curator_name => $curator->{name});

    $self->store_feature_relationshipprop($rel, community_curated =>
                                            $curator->{community_curated} ? 'true' : 'false');
  }
  if (defined $first_approved_timestamp) {
    $self->store_feature_relationshipprop($rel, first_approved_timestamp => $first_approved_timestamp);
  }
  if (defined $approved_timestamp) {
    $self->store_feature_relationshipprop($rel, approved_timestamp => $approved_timestamp);
  }
  if (defined $approver_email) {
    $self->store_feature_relationshipprop($rel, approver_email => $approver_email);
  }
  if (defined $canto_session) {
    $self->store_feature_relationshipprop($rel, canto_session => $canto_session);
  }
  if (defined $annotation_throughput_type) {
    $self->store_feature_relationshipprop($rel, annotation_throughput_type => $annotation_throughput_type);
  }
  if (@notes) {
    for my $note (@notes) {
      $self->store_feature_relationshipprop($rel, interaction_note => $note);
    }
  }

  return $rel;
}

=head2 store_interaction

 Usage   : $self->store_interaction(%args);
 Function:
 Args    :
  feature_a - a Sequence::Feature (bait)
  feature_b - a Sequence::Feature (prey)
  rel_type_name - 'physical_interaction' or 'genetic_interaction'
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

sub store_interaction {
  my $self = shift;

  my %args = @_;
  $args{is_inferred} = 0;

  my $rel_1 = $self->_store_interaction_helper(%args);

  my $evidence_type = $args{evidence_type};

  if (grep { $_ eq $evidence_type } @{$self->symmetrical_interaction_evidence_codes()}) {
    $args{is_inferred} = 1;
    ($args{feature_a}, $args{feature_b}) = ($args{feature_b}, $args{feature_a});
    return ($rel_1, $self->_store_interaction_helper(%args));
  } else {
    return $rel_1;
  }
}

1;
