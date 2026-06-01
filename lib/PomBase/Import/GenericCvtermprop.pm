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
has separator_char => (is => 'rw', init_arg => undef);
has chebi_cvterms => (is => 'rw', init_arg => undef);
has ignore_missing_cvterms => (is => 'rw', init_arg => undef);

sub BUILD {
  my $self = shift;
  my $property_name = undef;
  my $termid_column = undef;
  my $property_value_column = undef;
  my $separator_char = "\t";
  my %chebi_cvterms = ();
  my $ignore_missing_cvterms = 0;

  my @opt_config = ("property-name=s" => \$property_name,
                    "termid-column=s" => \$termid_column,
                    "property-value-column=s" => \$property_value_column,
                    "separator-char=s" => \$separator_char,
                    "ignore-missing-cvterms" => \$ignore_missing_cvterms,
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

  $self->separator_char($separator_char);

  if ($ignore_missing_cvterms) {
    my $chebi_dbxref_rs = $self->chado()->resultset('General::Dbxref')
      ->search({ 'db.name' => 'CHEBI', cvterm => { -not => undef } }, { join => ['db', 'cvterm'] });

    while (defined (my $dbxref = $chebi_dbxref_rs->next())) {
      $chebi_cvterms{"CHEBI:" . $dbxref->accession()} = 1;
    }
  }

  $self->ignore_missing_cvterms($ignore_missing_cvterms);

  $self->chebi_cvterms(\%chebi_cvterms);
}

sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $property_name = $self->property_name();

  my $sep_char = $self->separator_char();
  my $chebi_cvterms = $self->chebi_cvterms();
  my $ignore_missing_cvterms = $self->ignore_missing_cvterms();

  my $reader = Text::CSV->new({ sep_char => $sep_char, allow_loose_quotes => 1 });

  while (my $columns_ref = $reader->getline($fh)) {
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

    if ($ignore_missing_cvterms && !exists $chebi_cvterms->{$termid}) {
      next;
    }

    my $cvterm = $self->find_cvterm_by_term_id($termid);

    if (!defined $cvterm) {
      warn "can't find cvterm for $termid\n";
      next;
    }

    my $property_value = $columns_ref->[$self->property_value_column() - 1];

    my $cvtermprop =
      $self->store_cvtermprop($cvterm, $property_name, $property_value);
  }
}

1;
