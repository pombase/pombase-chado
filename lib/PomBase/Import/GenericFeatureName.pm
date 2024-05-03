package PomBase::Import::GenericFeatureName;

=head1 NAME

PomBase::Import::GenericFeatureName - load feature IDs and names
    from a TSV file and set the feature name

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::GenericFeatureName

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

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::FeatureFinder';

has verbose => (is => 'ro');

sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $tsv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  my $dbh = $self->chado()->storage()->dbh();
  my $update_sth =
    $dbh->prepare("UPDATE feature SET name = ? WHERE uniquename = ?");

  while (my $columns_ref = $tsv->getline($fh)) {
    my $col_count = scalar(@$columns_ref);

    die "line $. doesn't have two columns\n" if $col_count != 2;

    my ($feature_uniquename, $feature_name) = @$columns_ref;

    $update_sth->execute($feature_name, $feature_uniquename);
  }
}

1;
