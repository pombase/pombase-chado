package PomBase::Chado::InferParalogs;

=head1 NAME

PomBase::Chado::InferParalogs - Infer paralogs using orthologs

=head1 DESCRIPTION

Infer paralogs from orthologs.  Create paralog annotations for
all genes that share a common ortholog.

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::InferParalogs

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

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::OrthologMap';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has this_taxonid => (is => 'rw', init_arg => undef);
has ortholog_taxonid => (is => 'rw', init_arg => undef);

has organism => (is => 'rw', init_arg => undef);
has ortholog_organism => (is => 'rw', init_arg => undef);

with 'PomBase::Role::ParalogStorer';

sub BUILD
{
  my $self = shift;

  my $this_taxonid = undef;
  my $ortholog_taxonid = undef;

  my @opt_config = ("this-taxonid=s" => \$this_taxonid,
                    "ortholog-taxonid=s" => \$ortholog_taxonid,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $this_taxonid || length $this_taxonid == 0) {
    die "no --this-taxonid passed to the InferParalogs processor\n";
  }

  my $organism = $self->find_organism_by_taxonid($this_taxonid);
  $self->organism($organism);

  if (!defined $ortholog_taxonid || length $ortholog_taxonid == 0) {
    die "no --ortholog-taxonid passed to the InferParalogs processor\n";
  }

  my $ortholog_organism = $self->find_organism_by_taxonid($ortholog_taxonid);
  $self->ortholog_organism($ortholog_organism);
}


sub process
{
  my $self = shift;

  my %ortholog_map =
    $self->ortholog_map($self->organism(), $self->ortholog_organism());

  my @groups =
    map {
      my $group = $_;
      { genes => $group, date => undef };
    }
    grep {
       @$_ > 1;
    }
    values %ortholog_map;

  $self->store_paralog_groups(@groups);
}

1;
