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

requires 'find_or_create_cvterm';
requires 'chado';

has stored_cvterms => (is => 'ro',
                       lazy => 1, builder => '_build_stored_cvterms');

# preinitialise the hash of ranks of the existing feature_cvterms
method _build_stored_cvterms() {
  my $chado = $self->chado();

  my $rs = $chado->resultset('Sequence::FeatureCvterm')->search();

  my $stored_cvterms = {};

  while (defined (my $fc = $rs->next())) {
    my $key = $fc->cvterm_id() . '-' . $fc->feature_id() . '-' . $fc->pub_id();
    my $rank = $fc->rank();
    if (exists $stored_cvterms->{$key}) {
      if ($rank > $stored_cvterms->{$key}) {
        $stored_cvterms->{$key} = $rank;
      } else {
        next;
      }
    } else {
      $stored_cvterms->{$key} = $rank;
    }
  }

  return $stored_cvterms;
}

method create_feature_cvterm($chado_object, $cvterm, $pub, $is_not) {
  my $rs = $self->chado()->resultset('Sequence::FeatureCvterm');

  if (!defined $cvterm) {
    croak "cvterm not defined in create_feature_cvterm() for ",
      $chado_object->uniquename(), "\n";
  }

  my $systematic_id = $chado_object->uniquename();

  if (!defined $pub) {
    croak "no pub passed to create_feature_cvterm()";
  }

  my $rank;

  my $key = $cvterm->cvterm_id() . '-' . $chado_object->feature_id() . '-' . $pub->pub_id();

  if (exists $self->stored_cvterms()->{$key}) {
    $rank = ++$self->stored_cvterms()->{$key};
  } else {
    $self->stored_cvterms()->{$key} = 0;
    $rank = 0;
  }

  if ($self->verbose()) {
    warn "  storing feature_cvterm from: ", $chado_object->uniquename(),
      " to: ", $cvterm->name(), " pub: ", $pub->uniquename(), " is_not: ",
      ($is_not // 0), " rank: $rank\n";
  }

  my $create_args = { feature => $chado_object,
                      cvterm => $cvterm,
                      pub => $pub,
                      is_not => $is_not,
                      rank => $rank };

  return $rs->create($create_args);
}

my $current_year = 1900 + (localtime(time))[5];

func _fix_date($date) {
  if ($date =~ /(\d\d\d\d)-?(\d\d)-?(\d\d)/) {
    if ($1 > $current_year) {
      warn "date is in the future: $date\n";
    } else {
      if ($2 < 1 || $2 > 12) {
        warn "month ($2) not in range 1..12\n";
      }
      if ($3 < 1 || $3 > 31) {
        warn "day ($3) not in range 1..31\n";
      }
    }
    return "$1-$2-$3";
  } else {
    die qq|problem with date format of "$date", should be ISO ie. YYYY-MM-DD|;
  }
}

method add_feature_cvtermprop($feature_cvterm, $name, $value, $rank) {
  if (!defined $name) {
    die "no name for property\n";
  }
  if ($name eq 'expression') {
    # temporary hack to fix https://github.com/pombase/pombase-chado/issues/475
    warn 'FEAT: ', $feature_cvterm->feature()->uniquename();
    confess "expression not allowed as a feature_cvtermprop, value $value";
  }

  if (!defined $value) {
    die "no value when storing $name prop into feature_cvtermprop\n";
  }

  if (!defined $rank) {
    $rank = 0;
  }

  if ($name eq 'date') {
    $value = _fix_date($value);
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
