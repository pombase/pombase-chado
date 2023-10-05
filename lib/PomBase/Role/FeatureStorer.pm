package PomBase::Role::FeatureStorer;

=head1 NAME

PomBase::Role::FeatureStorer - Code for storing features in Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::FeatureStorer

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Try::Tiny;

use feature qw(state);

use Moose::Role;

use Carp::Assert;

with 'PomBase::Role::Embl::StoreLocation';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';

requires 'find_or_create_pub';

sub store_feature {
  my $self = shift;
  my $uniquename = shift;
  my $name = shift;
  my $synonyms = shift;
  my $so_type = shift;
  my $organism = shift;

  my $feature_type_term =
    $self->get_cvterm('sequence', $so_type) //
    $self->get_cvterm('PomBase sequence feature types', $so_type);

  use Carp qw(cluck);

  cluck "not enough arguments for store_feature()" unless defined $organism;

  warn "  storing $uniquename/", ($name ? $name : 'no_name'),
    " ($so_type)\n" if $self->verbose();

  die "can't find SO cvterm for $so_type\n" unless defined $feature_type_term;

  my %create_args = (
    type_id => $feature_type_term->cvterm_id(),
    uniquename => $uniquename,
    organism_id => $organism->organism_id(),
  );

  if ($so_type ne 'intron') {
    $create_args{name} = $name;
  }

  my $feature_rs = $self->chado()->resultset('Sequence::Feature');

  my $new_feature = undef;

  try {
    $new_feature = $feature_rs->create({ %create_args });
  } catch {
    use Carp 'longmess';
    warn "create() failed '$_':", longmess();
  };

  return $new_feature;
}

sub find_or_create_synonym {
  my $self = shift;
  my $synonym_name = shift;
  my $type_name = shift;

  my $type = $self->get_cvterm('synonym_type', $type_name);

  if (!defined $type) {
    die "no synonym type cvterm found for $type_name\n";
  }

  return $self->chado()->resultset('Sequence::Synonym')->find_or_create({
    name => $synonym_name,
    synonym_sgml => $synonym_name,
    type_id => $type->cvterm_id(),
  });
}

sub store_feature_synonym {
  my $self = shift;
  my $feature = shift;
  my $synonym_name = shift;
  my $type = shift;
  my $is_current = shift;
  my $pubmed_id = shift;

  $is_current //= 1;

  my $synonym = $self->find_or_create_synonym($synonym_name, $type);

  my $pub = $self->find_or_create_pub($pubmed_id || 'null');

  warn "   creating synonym for ", $feature->uniquename(), " - $synonym_name, type: $type\n"
    if $self->verbose();

  return $self->chado()->resultset('Sequence::FeatureSynonym')->find_or_create({
    feature_id => $feature->feature_id(),
    synonym_id => $synonym->synonym_id(),
    pub_id => $pub->pub_id(),
    is_current => $is_current,
  });
}

=head2 store_synonym_if_missing

 Usage   : $self->store_synonym_if_missing($allele, $synonym);
 Function: Take a list of synonyms for an allele and store if those
           doesn't already exist
 Args    : $allele
           $synonyms - a reference of a list of synonyms
           $pubmed_id
 Returns : nothing

=cut

sub store_synonym_if_missing {
  my $self = shift;
  my $allele = shift;
  my $synonyms = shift;
  my $pubmed_id = shift;

  my $chado = $self->chado();

  my @existing_synonyms = $chado->resultset('Sequence::FeatureSynonym')
    ->search({ feature_id => $allele->feature_id() },
             { prefetch => 'synonym' })->all();

  my @existing_names = map {
    $_->synonym()->name();
  } @existing_synonyms;

  for my $new_synonym (@{$synonyms}) {
    if (!grep { $_ eq $new_synonym } @existing_names) {
      $self->store_feature_synonym($allele, $new_synonym, 'exact', 1,
                                   $pubmed_id);
    }
  }
}


sub store_feature_and_loc {
  my $self = shift;
  my $feature = shift;
  my $chromosome = shift;
  my $so_type = shift;
  my $start_arg = shift;
  my $end_arg = shift;

  my $chado = $self->chado();

  my ($uniquename, $transcript_uniquename, $gene_uniquename) =
    $self->get_uniquename($feature, $so_type);

  if ($so_type eq 'gene') {
    $uniquename = $gene_uniquename;
  }

  my $name = undef;
  my $reserved_name = undef;

  if ($feature->has_tag('primary_name')) {
    my @primary_names = $feature->get_tag_values('primary_name');

    if (@primary_names > 1) {
      warn "$uniquename has more than one /primary_name\n";
    }

    $name = $primary_names[0];
  } else {
    if ($feature->has_tag('reserved_name')) {
      my @reserved_names = $feature->get_tag_values('reserved_name');

      if (@reserved_names > 1) {
        warn "$uniquename has more than one /reserved_name\n";
      }

      $reserved_name = $reserved_names[0];
    } else {
      if ($so_type eq 'gene') {
        warn "no /primary_name qualifier for $uniquename\n" if $self->verbose();
      }
    }
  }

  my @synonyms = ();

  if ($feature->has_tag('synonym')) {
    @synonyms = $feature->get_tag_values('synonym');
  }

  if ($feature->has_tag('pseudo')) {
    $so_type = 'pseudogene';
  }

  my $chado_feature = $self->store_feature($uniquename, $name, [], $so_type,
                                           $chromosome->organism());

  my $start = $start_arg // $feature->location()->start();
  my $end = $end_arg // $feature->location()->end();
  my $strand = $feature->location()->strand();

  $self->store_location($chado_feature, $chromosome, $strand, $start, $end);

  for my $synonym (@synonyms) {
    next if $synonym eq $uniquename;
    next if $synonym eq $gene_uniquename;
    next if defined $name and $synonym eq $name;

    $self->store_feature_synonym($chado_feature, $synonym, 'exact', undef);
  }

  if (defined $reserved_name) {
    $self->store_feature_synonym($chado_feature, $reserved_name, 'reserved_name', undef);
  }

  if ($feature->has_tag('obsolete_name')) {
    my @obsolete_names = $feature->get_tag_values('obsolete_name');
    for my $obsolete_name (@obsolete_names) {
      $self->store_feature_synonym($chado_feature, $obsolete_name, 'obsolete_name', 0, undef);
    }
  }

  return $chado_feature;
}

sub store_featureprop {
  my $self = shift;
  my $feature = shift;
  my $type_name = shift;
  my $value = shift;

  state $ranks = {};

  assert (defined $value, "no value passed to store_featureprop()");

  my $type_cvterm = $self->get_cvterm('PomBase feature property types', $type_name);

  if (!defined $type_cvterm) {
    die qq|no cvterm found for featureprop type $type_name\n|;
  }

  if (!exists $ranks->{$type_name}) {
    $ranks->{$type_name} = {};

    my $featureprop_rs = $self->chado()->resultset('Sequence::Featureprop')
      ->search({
        'me.type_id' => $type_cvterm->cvterm_id(),
      }, {
        prefetch => 'feature'
      });

    for my $prop ($featureprop_rs->all()) {
      my $prop_rank = $prop->rank();

      my $current_rank =
        $ranks->{$type_name}->{$prop->feature()->feature_id()};

      if (!defined $current_rank || $current_rank < $prop_rank) {
        $ranks->{$type_name}->{$prop->feature()->feature_id()} = $prop_rank;
      }
    }
  }

  my $rank;

  if (!exists $ranks->{$type_name}->{$feature->feature_id()}) {
    $ranks->{$type_name}->{$feature->feature_id()} = -1;
  }

  $rank = ++$ranks->{$type_name}->{$feature->feature_id()};

  warn "  storing featureprop for ", $feature->uniquename(), " $type_name $value\n" if $self->verbose();

  die "can't store a reference as a value\n" if ref $value;

  $self->chado()->resultset('Sequence::Featureprop')->create({
    feature_id => $feature->feature_id(),
    type_id => $type_cvterm->cvterm_id(),
    value => $value,
    rank => $rank,
  });
}

sub store_featureprop_pub {
  my $self = shift;
  my $featureprop = shift;
  my $pub_uniquename = shift;

  my $pub = $self->find_or_create_pub($pub_uniquename);

  $self->chado()->resultset('Sequence::FeaturepropPub')->create({
    featureprop_id => $featureprop->featureprop_id(),
    pub_id => $pub->pub_id(),
  });
}

sub get_new_uniquename {
  my $self = shift;
  my $prefix = shift;
  my $first_suffix = shift;

  my $next_suffix = $first_suffix // 1;
  my $rs = $self->chado()->resultset('Sequence::Feature')
                ->search({ uniquename => { -like => $prefix . '%' } });

  while (defined (my $feature = $rs->next())) {
    my $uniquename = $feature->uniquename();

    if ($uniquename =~ /^$prefix(\d+)$/) {
      if ($1 >= $next_suffix) {
        $next_suffix = $1 + 1;
      }
    }
  }

  return $prefix . $next_suffix;
}

sub store_feature_pub {
  my $self = shift;
  my $feature = shift;
  my $pub = shift;

  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $sth =
    $dbh->prepare("
INSERT INTO feature_pub(feature_id, pub_id) VALUES (?, ?) ON CONFLICT DO NOTHING;
");

  $sth->execute($feature->feature_id(), $pub->pub_id());
}

1;
