package PomBase::Role::XrefStorer;

=head1 NAME

PomBase::Role::XrefStorer - Code for storing dbxrefs and publications in Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::XrefStorer

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

use feature qw(state);

use Try::Tiny;
use Moose::Role;

requires 'chado';

sub find_or_create_dbxref {
  my $self = shift;
  my $db = shift;
  my $accession = shift;

  my $dbxref_rs = $self->chado()->resultset('General::Dbxref');
  return $dbxref_rs->find_or_create({ db_id => $db->db_id(),
                                      accession => $accession });
}

sub find_or_create_pub {
  my $self = shift;
  my $identifier = shift;

  state $cache = {};

  if (exists $cache->{$identifier}) {
    return $cache->{$identifier};
  }

  my $pub_rs = $self->chado()->resultset('Pub::Pub');

  my $paper_cvterm = $self->find_cvterm_by_name('PomBase publication types', 'paper');

  my $pub = $pub_rs->find_or_create({ uniquename => $identifier,
                                      type_id => $paper_cvterm->cvterm_id() });

  $cache->{$identifier} = $pub;

  return $pub;
}

sub create_pubprop {
  my $self = shift;
  my $pub = shift;
  my $type_name = shift;
  my $value = shift;

  my $type_term = $self->find_cvterm_by_name('pubprop_type', $type_name);
  if (!defined $type_term) {
    croak "no pubprop_type term for: $type_name\n";
  }
  if (!defined $value) {
    croak "can't store null value for $type_name\n";
  }

  my $pubprop_rs = $self->chado()->resultset('Pub::Pubprop');
  return $pubprop_rs->create({ pub_id => $pub->pub_id(),
                               type_id => $type_term->cvterm_id(),
                               value => $value });
}

sub find_db_by_name {
  my $self = shift;
  my $db_name = shift;

  die 'no $db_name' unless defined $db_name;

  state $cache = {};

  if (exists $cache->{$db_name}) {
    return $cache->{$db_name};
  }

  my $db = $self->chado()->resultset('General::Db')->find({ name => $db_name });
  $cache->{$db_name} = $db;
  die "no db with name: $db_name" unless defined $db;

  return $db;
}

sub add_feature_dbxref {
  my $self = shift;
  my $feature = shift;
  my $dbxref_value = shift;

  if ($dbxref_value =~ /^((.*):(.*))/) {
    my $db_name = $2;
    my $accession = $3;

    my $db = $self->find_db_by_name($db_name);
    my $dbxref = $self->find_or_create_dbxref($db, $accession);

    try {
      $self->chado()->txn_do(sub {
                               $self->chado()
                                 ->resultset('Sequence::FeatureDbxref')->create({
                                   feature_id => $feature->feature_id(),
                                   dbxref_id => $dbxref->dbxref_id(),
                                 });
                             });
    }
    catch {
      my $existing_rs = $self->chado()
        ->resultset('Sequence::FeatureDbxref')
        ->search({
          feature_id => $feature->feature_id(),
          dbxref_id => $dbxref->dbxref_id(),
        });
      if ($existing_rs->count() > 0) {
        warn "failed to store db_xref $dbxref_value for ",
          $feature->uniquename(), " - already stored\n";
      } else {
        warn "failed to store db_xref $dbxref_value for ",
          $feature->uniquename(), ": $_\n";
      }

    }
  } else {
    warn "unknown dbxref format ($dbxref_value) for ", $feature->uniquename(), "\n";
  }
}

sub get_pub_from_db_xref {
  my $self = shift;
  my $qual = shift;
  my $db_xref = shift;

  if (defined $db_xref) {
    if ($db_xref =~ /^(?:(\w+):(.+))/) {
      my $id_part = $2;
      if ($1 ne 'PMID' || $id_part =~ /^\d+$/) {
        return $self->find_or_create_pub($db_xref);
      }
      # fall through
    }
    warn "qualifier ($qual) has unknown format db_xref (", $db_xref,
      ") - using null publication\n";
    return $self->objs()->{null_pub};
  } else {
    warn "qualifier ($qual)",
      " has no db_xref - using null publication\n" if $self->verbose();
    return $self->objs()->{null_pub};
  }

}

sub create_feature_pub {
  my $self = shift;
  my $feature = shift;
  my $pub = shift;

  try {
    $self->chado()->txn_do(sub {
                             $self->chado()
                               ->resultset('Sequence::FeaturePub')
                               ->create({
                                 feature => $feature,
                                 pub => $pub,
                               });
                           });
  }
  catch {
    my $existing_rs = $self->chado()
      ->resultset('Sequence::FeaturePub')
      ->search({ feature_id => $feature->feature_id(),
                 pub_id => $pub->pub_id() });
    if ($existing_rs->count() > 0) {
      warn "failed to store reference ", $pub->uniquename(), " for ",
        $feature->uniquename(), " - already stored\n";
    } else {
      warn "failed to store reference ", $pub->uniquename(), " for ",
        $feature->uniquename(), ": $_\n";
    }
  };
}

1;
