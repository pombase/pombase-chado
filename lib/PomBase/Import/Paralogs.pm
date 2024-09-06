package PomBase::Import::Paralogs;

=head1 NAME

PomBase::Import::Paralogs - Load paralogs in tab delimited format and
                            store in Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Paralogs

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose;

use Text::Trim qw(trim);
use Text::CSV;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::Embl::FeatureRelationshipPubStorer';
with 'PomBase::Role::Embl::FeatureRelationshippropStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);
has organism => (is => 'rw', init_arg => undef);

with 'PomBase::Role::ParalogStorer';

sub BUILD
{
  my $self = shift;

  my $organism_taxonid = undef;

  my @opt_config = ("organism-taxonid=s" => \$organism_taxonid,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }


  if (!defined $organism_taxonid) {
    die "the --organism-taxonid argument is required\n";
  }

  my $organism = $self->find_organism_by_taxonid($organism_taxonid);
  $self->organism($organism);

}

=head2 load

 Usage   : $paralog_import->load($fh);
 Function: Load paralogs in tab-delimited format from a file handle.
           The input must have two columns.  Column 1 has the
           identifiers for a group of paralogous genes separated
           by commas.  Column 2 is an optional date
 Args    : $fh - a file handle
 Returns : nothing

=cut

sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $csv = Text::CSV->new({ sep_char => "\t" });

  $csv->column_names(qw(genes date));

  my @groups = ();

  ROW: while (my $columns_ref = $csv->getline_hr($fh)) {
    my $genes = trim($columns_ref->{"genes"});
    my $date = $columns_ref->{"date"};
    if (defined $date) {
      $date = trim($date);
      if (length $date == 0) {
        $date = undef;
      }
    }

    my @genes = split /,/, $genes;

    push @groups, { genes => \@genes, date => $date };
  }

  $self->store_paralog_groups(@groups);
}

1;

