package PomBase::Retrieve::Orthologs;

=head1 NAME

PomBase::Retrieve::Orthologs - Retrieve orthologs from Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::Orthologs

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

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
has other_organism_field_name => (is => 'rw');
has sensible_ortholog_direction => (is => 'rw');

sub BUILDARGS
{
  my $class = shift;
  my %args = @_;

  my $other_organism_taxonid = undef;
  my $other_organism_field_name = 'name';

  # PomBase doesn't have a sensible direction (ie pombe genes are the object
  # in the orthologous_to relations), so default to false
  my $sensible_ortholog_direction = 0;

  my @opt_config = ("other-organism-taxon-id=s" => \$other_organism_taxonid,
                    "other-organism-field-name=s" => \$other_organism_field_name,
                    "sensible-ortholog-direction" => \$sensible_ortholog_direction,
                  );

  if (!GetOptionsFromArray($args{options}, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $other_organism_taxonid) {
    die "no --other-organism-taxon-id argument\n";
  }

  $args{other_organism_taxonid} = $other_organism_taxonid;
  $args{other_organism_field_name} = $other_organism_field_name;
  $args{sensible_ortholog_direction} = $sensible_ortholog_direction;

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

  my $other_org_identifier_field_name = $self->other_organism_field_name();

  my $dbh = $self->chado()->storage()->dbh();

  my $transposon_temp = "
CREATE TEMP TABLE transposons_temp AS
SELECT fc.feature_id
FROM feature_cvterm fc
  JOIN cvterm t ON fc.cvterm_id = t.cvterm_id
  JOIN cv ON t.cv_id = cv.cv_id
WHERE cv.name = 'PomBase gene characterisation status'
  AND t.name = 'transposon'";


  my $protein_temp = "
CREATE TEMP TABLE protein_coding_genes AS
SELECT o.feature_id, o.uniquename
FROM feature_relationship r, cvterm rt, feature o, feature s, cvterm st
WHERE r.subject_id = s.feature_id
  AND r.object_id = o.feature_id
  AND r.type_id = rt.cvterm_id
  AND s.type_id = st.cvterm_id
  AND st.name = 'mRNA'
  AND s.organism_id = ?
  AND r.subject_id NOT IN (select feature_id from transposons_temp)
  AND r.object_id NOT IN (select feature_id from transposons_temp);";

  my $main_feature = 'object';
  my $other_org_feature = 'subject';

  if ($self->sensible_ortholog_direction()) {
    ($main_feature, $other_org_feature) = ('subject', 'object');
  }

  my $ortholog_temp = "
CREATE TEMP TABLE ortholog_list AS
SELECT distinct $main_feature.feature_id, $main_feature.uniquename as o_un,
                $other_org_feature.$other_org_identifier_field_name as s_name
  FROM feature $main_feature
  LEFT OUTER JOIN feature_relationship r
    ON r.type_id = (select cvterm_id from cvterm where name = 'orthologous_to')
   AND $main_feature.feature_id = r.${main_feature}_id
  JOIN feature $other_org_feature
    ON $other_org_feature.feature_id = r.${other_org_feature}_id AND $main_feature.organism_id = ? AND $other_org_feature.organism_id = ?
 WHERE $main_feature.feature_id in (select feature_id from protein_coding_genes)";

  my $orthologs_query = "
CREATE TEMP TABLE full_table AS
SELECT o_un, s_name
  FROM ortholog_list
 UNION
SELECT uniquename AS o_un, 'NONE' as s_name
  FROM protein_coding_genes
 WHERE feature_id NOT IN (select feature_id from ortholog_list)
 ORDER BY o_un, s_name
";

  my $query = "
SELECT o_un, string_agg(CASE WHEN s_name IS NULL THEN 'NONE' ELSE s_name END, '|')
  FROM full_table
 GROUP BY o_un
 ORDER BY o_un";

  my $it = do {
    my $sth = $dbh->prepare($transposon_temp);
    $sth->execute()
      or die "Couldn't execute: " . $sth->errstr;

    $sth = $dbh->prepare($protein_temp);
    $sth->execute($self->organism()->organism_id())
      or die "Couldn't execute: " . $sth->errstr;

    $sth = $dbh->prepare($ortholog_temp);
    $sth->execute($self->organism->organism_id(), $other_organism->organism_id())
      or die "Couldn't execute: " . $sth->errstr;

    $sth = $dbh->prepare($orthologs_query);
    $sth->execute() or die "Couldn't execute: " . $sth->errstr;

    $sth = $dbh->prepare($query);
    $sth->execute() or die "Couldn't execute: " . $sth->errstr;

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
