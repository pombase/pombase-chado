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

use perl5i::2;
use Moose::Role;

requires 'chado';

method find_or_create_dbxref($db, $accession) {
  my $dbxref_rs = $self->chado()->resultset('General::Dbxref');
  return $dbxref_rs->find_or_create({ db_id => $db->db_id(),
                                      accession => $accession });
}

method find_or_create_pub($identifier) {
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

method create_pubprop($pub, $type_name, $value) {
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

method find_db_by_name($db_name) {
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

method add_feature_dbxref($feature, $dbxref_value) {
  if ($dbxref_value =~ /^((.*):(.*))/) {
    my $db_name = $2;
    my $accession = $3;

    my $db = $self->find_db_by_name($db_name);
    my $dbxref = $self->find_or_create_dbxref($db, $accession);

    $self->chado()->resultset('Sequence::FeatureDbxref')->create({
      feature_id => $feature->feature_id(),
      dbxref_id => $dbxref->dbxref_id(),
    });
  } else {
    warn "unknown dbxref format ($dbxref_value) for ", $feature->uniquename(), "\n";
  }
}

method get_pub_from_db_xref($qual, $db_xref) {
  if (defined $db_xref) {
    if ($db_xref =~ /^(?:(\w+):(.+))/) {
      if ($1 ne 'PMID' || $2->is_integer()) {
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

method create_feature_pub($feature, $pub) {
  $self->chado()->resultset('Sequence::FeaturePub')->create({
    feature => $feature,
    pub => $pub,
  });
}

1;
