package PomBase::Retrieve::SimpleOrthologs;

=head1 NAME

PomBase::Retrieve::SimpleOrthologs - Retrieve orthologs from Chado in a
            simple one line per ortholog pair format, using Chado
            uniquenames / systematic IDs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::SimpleOrthologs

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2021 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;
use Moose;

use Iterator::Simple qw(iterator);

use Getopt::Long qw(GetOptionsFromArray :config pass_through);

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';

has other_organism_taxonid => (is => 'rw');
has swap_direction => (is => 'rw');

sub BUILDARGS
{
  my $class = shift;
  my %args = @_;

  my $other_organism_taxonid = undef;
  my $swap_direction;

  my @opt_config = ("other-organism-taxon-id=s" => \$other_organism_taxonid,
                    "swap-direction" => \$swap_direction,
                  );

  if (!GetOptionsFromArray($args{options}, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $other_organism_taxonid) {
    die "no --other-organism-taxon-id argument\n";
  }

  $args{other_organism_taxonid} = $other_organism_taxonid;
  $args{swap_direction} = $swap_direction // 0;

  return \%args;
}

sub retrieve {
  my $self = shift;

  my $chado = $self->chado();

  my $taxon_id = $self->other_organism_taxonid();

  my $other_organism = $self->find_organism_by_taxonid($taxon_id);

  if (!defined $other_organism) {
    die "can't organism with taxon ID $taxon_id in the database\n";
  }

  my $dbh = $self->chado()->storage()->dbh();

  my $query = "
SELECT o.uniquename, s.uniquename
  FROM feature_relationship rel
  JOIN cvterm t ON rel.type_id = t.cvterm_id
  JOIN feature s ON rel.subject_id = s.feature_id
  JOIN feature o ON rel.object_id = o.feature_id
WHERE s.organism_id = ?
  AND o.organism_id = ?
  AND t.name = 'orthologous_to'";

  my $it = do {
    my $sth = $dbh->prepare($query);

    my @execute_args;
    if ($self->swap_direction()) {
      @execute_args = ($other_organism->organism_id(),
                       $self->organism()->organism_id());
    } else {
      @execute_args = ($self->organism()->organism_id(),
                       $other_organism->organism_id());
    }
    $sth->execute(@execute_args)
      or die "Couldn't execute: " . $sth->errstr;

    iterator {
      my @data = $sth->fetchrow_array();
      if (@data) {
        return [@data];
      } else {
        return undef;
      }
    };
  };
}

sub header {
  my $self = shift;
  return '';
}

sub format_result {
  my $self = shift;
  my $res = shift;

  return join "\t", @$res;
}

1;
