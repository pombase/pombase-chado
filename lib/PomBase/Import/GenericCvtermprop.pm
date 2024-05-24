package PomBase::Import::GenericCvtermprop;

=head1 NAME

PomBase::Import::GenericCvtermprop - Load cvtermprops from a delimited file
   containing the cvterm ID and the new property value

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::GenericProperty

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2024 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Try::Tiny;

use Moose;

use Text::CSV;
use Getopt::Long qw(GetOptionsFromArray);

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::CvtermpropStorer';

has termid_column => (is => 'rw', init_arg => undef);
has property_name => (is => 'rw', init_arg => undef);
has property_value_column => (is => 'rw', init_arg => undef);

sub BUILD {
  my $self = shift;
  my $property_name = undef;
  my $termid_column = undef;
  my $property_value_column = undef;

  my @opt_config = ("property-name=s" => \$property_name,
                    "termid-column=s" => \$termid_column,
                    "property-value-column=s" => \$property_value_column,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    die "option parsing failed";
  }

  if (!defined $termid_column) {
    die "no --termid-column argument\n";
  }

  $self->termid_column($termid_column);

  if (defined $property_value_column) {
    $self->property_value_column($property_value_column);
  } else {
    die "no --property-value-column passed to the GenericCvtermprop loader\n";
  }

  if (!defined $property_name || length $property_name == 0) {
    die "no --property-name passed to the GenericProperty loader\n";
  }

  $self->property_name($property_name);
}

sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $property_name = $self->property_name();

  my $tsv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  while (my $columns_ref = $tsv->getline($fh)) {
    my $col_count = scalar(@$columns_ref);

    next if $col_count == 0;

    if ($columns_ref->[0] =~ /^#/) {
      next;
    }

    if ($self->termid_column() &&
        $self->termid_column() > $col_count) {
      warn "line $. is too short: the value for --termid-column is ",
        $self->termid_column(), "\n";
      next;
    }

    if ($self->property_value_column() > $col_count) {
      warn "line $. is too short: the value for --property-value-column is ",
        $self->property_value_column(), "\n";
      next;
    }

    my $termid = $columns_ref->[$self->termid_column() - 1];

    my $cvterm = $self->find_cvterm_by_term_id($termid);

    if (!defined $cvterm) {
      die "can't find term for $termid\n";
    }

    my $property_value = $columns_ref->[$self->property_value_column() - 1];

    my $cvtermprop =
      $self->store_cvtermprop($cvterm, $property_name, $property_value);
  }
}

1;
