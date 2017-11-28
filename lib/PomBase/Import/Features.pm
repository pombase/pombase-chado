package PomBase::Import::Features;

=head1 NAME

PomBase::Import::Features - load feature without coords or sequence

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Features

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

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has organism => (is => 'rw', init_arg => undef);
has feature_type => (is => 'rw', init_arg => undef);
has uniquename_column => (is => 'rw', init_arg => undef);
has name_column => (is => 'rw', init_arg => undef);
has ignore_lines_matching => (is => 'rw', init_arg => undef);
has ignore_short_lines => (is => 'rw', init_arg => undef);
has column_filters => (is => 'rw', init_arg => undef);

sub BUILD
{
  my $self = shift;

  my $organism_taxonid = undef;
  my $uniquename_column = undef;
  my $name_column = undef;
  my $feature_type = undef;
  my $ignore_lines_matching = '';
  my $ignore_short_lines = 0;
  my @column_filters = ();

  my @opt_config = ("organism-taxonid=s" => \$organism_taxonid,
                    "feature-type=s" => \$feature_type,
                    "column-filter=s" => \@column_filters,
                    "uniquename-column=s" => \$uniquename_column,
                    "name-column=s" => \$name_column,
                    "ignore-lines-matching=s" => \$ignore_lines_matching,
                    "ignore-short-lines" => \$ignore_short_lines,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $organism_taxonid || length $organism_taxonid == 0) {
    die "no --organism-taxonid passed to the Features loader\n";
  }

  my $organism = $self->find_organism_by_taxonid($organism_taxonid);

  if (!defined $organism) {
    die "can't find organism with taxon ID: $organism_taxonid\n";
  }

  $self->organism($organism);

  if (!defined $uniquename_column) {
    die "no --uniquename-column passed to the Features loader\n";
  }

  $self->uniquename_column($uniquename_column - 1);

  if (!defined $name_column) {
    die "no --name-column passed to the Features loader\n";
  }

  $self->name_column($name_column - 1);

  if (!defined $feature_type) {
    die "no --feature-type passed to the Features loader\n";
  }

  $self->feature_type($feature_type);

  $self->ignore_lines_matching($ignore_lines_matching);
  $self->ignore_short_lines($ignore_short_lines);
  $self->column_filters(\@column_filters);
}

method load($fh) {
  my $uniquename_column = $self->uniquename_column();
  my $name_column = $self->name_column();
  my $feature_type_name = $self->feature_type();
  my $organism = $self->organism();
  my $ignore_short_lines = $self->ignore_short_lines();
  my $ignore_lines_matching_string = $self->ignore_lines_matching();


  my %filter_conf = ();

  for my $filter_config (@{$self->column_filters()}) {
    if ($filter_config =~ /^(\d)=(.*)/) {
      $filter_conf{$1 - 1} = $2;
    } else {
      die qq|unknown format for --filter-config: "$filter_config"|;
    }
  }

 LINE:
  while (<$fh>) {
    next if /^#|^!/;

    next if $ignore_lines_matching_string && /$ignore_lines_matching_string/;

    chomp $_;

    my @columns = split /\t/, $_;

    if (!$ignore_short_lines && $uniquename_column >= @columns) {
      die "not enough columns for --uniquename-column at: $_\n";
    }
    if (!$ignore_short_lines && $name_column >= @columns) {
      die "not enough columns for --name-column at: $_\n";
    }

    for my $filter_column (keys %filter_conf) {
      my $filter_value = $filter_conf{$filter_column};

      if ($columns[$filter_column] ne $filter_value) {
        next LINE;
      }
    }

    my $uniquename = $columns[$uniquename_column];
    my $name = $columns[$name_column] || undef;

    $self->store_feature($uniquename, $name, [], $feature_type_name, $organism);
  }
}

1;
