package PomBase::Check::DuplicateInteractions;

=head1 NAME

PomBase::Check::DuplicateInteractions - Check for duplicate interactions

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Check::DuplicateInteractions

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

method description() {
  return "Check for duplicate interactions";
}

with 'PomBase::Checker';

func _get_source($props) {
  my $source = $props->{source_database};

  if ($source eq 'PBO') {
    $source = 'PomBase';
  }

  if ($source) {
    if ($source eq 'PomBase') {
      my $session = $props->{canto_session};
      if ($session) {
        $source .= "(Canto: $session)";
      }

      my $date = $props->{date};
      if ($date) {
        $source .= "($date)";
      }
    }

    return $source;
  } else {
    return undef;
  }
}

method check() {
  my $chado = $self->chado();
  my %evidence_types = %{$self->config()->{evidence_types}};

  my %symmetrical_relation = ();

  map {
    my $ev_name = $_;

    my $symmetrical = $evidence_types{$ev_name}->{symmetrical};
    if ($symmetrical && lc $symmetrical ne 'no') {
      $symmetrical_relation{$ev_name} = 1;
    } else {
      $symmetrical_relation{$ev_name} = 0;
    }
  } keys %evidence_types;

  my $feature_rel_rs = $self->chado()->resultset('Sequence::FeatureRelationship')
    ->search({ -or => [ 'type.name' => 'interacts_genetically',
                        'type.name' => 'interacts_physically' ]},
             { join => 'type' });

  my %props = ();

  my @all_props =
    $self->chado()->resultset('Sequence::FeatureRelationshipprop')
      ->search({
        -or => [
          'type.name' => 'source_database',
          'type.name' => 'evidence',
          'type.name' => 'date',
          'type.name' => 'canto_session',
        ],
        feature_relationship_id => {
          -in => $feature_rel_rs->get_column('feature_relationship_id')->as_query(),
        }
      }, { join => 'type', prefetch => 'type' })
        ->all();

  map {
    my $type_name = $_->type()->name();

    $props{$_->feature_relationship_id()}->{$type_name} = $_->value();
   } @all_props;

  my $fr_prefetch_rs = $feature_rel_rs
    ->search({},
             {
               prefetch => ['subject', 'object', 'type',
                            { feature_relationship_pubs => 'pub' } ],
             });

  my %seen_rel = ();
  my @reciprocal_interactions_to_check = ();

  my $success = 1;

  while (defined (my $rel = $fr_prefetch_rs->next())) {
    my $sub_uniquename = $rel->subject()->uniquename();
    my $obj_uniquename = $rel->object()->uniquename();
    my $interaction_type_name = $rel->type()->name();
    my $pub_uniquename = $rel->feature_relationship_pubs()->first()->pub()->uniquename();
    my %this_rel_props = %{$props{$rel->feature_relationship_id()}};

    my $key_prefix = "$sub_uniquename <-$interaction_type_name-> $obj_uniquename";

    my $source = _get_source(\%this_rel_props);

    if (!defined $source) {
      warn "no source found for interaction $key_prefix\n";
      next;
    }

    my $evidence = $this_rel_props{evidence};

    if (!defined $evidence) {
      warn "no evidence found for interaction $key_prefix\n";
      next;
    }

    my $key_suffix = "from $pub_uniquename  $evidence";

    my $key = "$key_prefix  $key_suffix";

    if (exists $seen_rel{$key}) {
      my $other_rel = $seen_rel{$key};
      my $other_source = _get_source($props{$other_rel->feature_relationship_id()});
      warn "already exists: $key  sources: $source and $other_source\n";
      $success = 0;
    } else {
      $seen_rel{$key} = $rel;
    }

    if ($symmetrical_relation{$evidence}) {
      my $key_prefix_rev = "$obj_uniquename <-$interaction_type_name-> $sub_uniquename";
      my $key_rev = "$key_prefix_rev  $key_suffix";

      push @reciprocal_interactions_to_check, $key_rev;
    }
  }

  for my $reciprocal_key (@reciprocal_interactions_to_check) {
    if (!exists $seen_rel{$reciprocal_key}) {
      warn "missing annotation for: $reciprocal_key\n";
      $success = 0;
    }
  }

  return $success;
}
