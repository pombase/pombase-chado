package PomBase::Role::FeatureCvtermCreator;

=head1 NAME

PomBase::Role::FeatureCvtermCreator - Role for creating feature_cvterms and
                                      feature_cvtermprops

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::FeatureCvtermCreator

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

requires 'find_or_create_cvterm';

my %stored_cvterms = ();

method create_feature_cvterm($chado_object, $cvterm, $pub, $is_not) {
  my $rs = $self->chado()->resultset('Sequence::FeatureCvterm');

  if (!defined $cvterm) {
    croak "cvterm not defined in create_feature_cvterm() for ",
      $chado_object->uniquename(), "\n";
  }

  my $systematic_id = $chado_object->uniquename();

  warn "NO PUB\n" unless $pub;

  if (!exists $stored_cvterms{$cvterm->name()}{$systematic_id}{$pub->uniquename()}) {
    $stored_cvterms{$cvterm->name()}{$systematic_id}{$pub->uniquename()} = 0;
  }

  my $rank =
    $stored_cvterms{$cvterm->name()}{$systematic_id}{$pub->uniquename()}++;

  return $rs->create({ feature_id => $chado_object->feature_id(),
                       cvterm_id => $cvterm->cvterm_id(),
                       pub_id => $pub->pub_id(),
                       is_not => $is_not,
                       rank => $rank });
}


method add_feature_cvtermprop($feature_cvterm, $name, $value, $rank) {
  if (!defined $name) {
    die "no name for property\n";
  }
  if (!defined $value) {
    die "no value for $name\n";
  }

  if (!defined $rank) {
    $rank = 0;
  }

  if (ref $value eq 'ARRAY') {
    my @ret = ();
    for (my $i = 0; $i < @$value; $i++) {
      push @ret, $self->add_feature_cvtermprop($feature_cvterm,
                                               $name, $value->[$i], $i);
    }
    return @ret;
  }

  my $type = $self->find_or_create_cvterm($self->get_cv('feature_cvtermprop_type'),
                                          $name);

  my $rs = $self->chado()->resultset('Sequence::FeatureCvtermprop');

  warn "    adding feature_cvtermprop $name => $value\n" if $self->verbose();

  return $rs->create({ feature_cvterm_id =>
                         $feature_cvterm->feature_cvterm_id(),
                       type_id => $type->cvterm_id(),
                       value => $value,
                       rank => $rank });
}

1;
