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

use perl5i::2;
use Moose;

use List::Gen 'iterate';

use Getopt::Long qw(GetOptionsFromArray :config pass_through);

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';

has other_organism_taxonid => (is => 'rw');

sub BUILDARGS
{
  my $class = shift;
  my %args = @_;

  my $other_organism_taxonid = undef;

  my @opt_config = ("other-organism-taxon-id=s" => \$other_organism_taxonid,
                  );

  if (!GetOptionsFromArray($args{options}, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $other_organism_taxonid) {
    die "no --other-organism-taxon-id argument\n";
  }

  $args{other_organism_taxonid} = $other_organism_taxonid;

  return \%args;
}

method retrieve() {
  my $chado = $self->chado();

  my $taxon_id = $self->other_organism_taxonid();

  my $other_organism = $self->find_organism_by_taxonid($taxon_id);

  if (!defined $other_organism) {
    die "can't organism with taxon ID $taxon_id in the database\n";
  }

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

  my $ortholog_temp = "
CREATE TEMP TABLE ortholog_list AS
SELECT distinct object.feature_id, object.uniquename as o_un, subject.name as s_name
  FROM feature object
  LEFT OUTER JOIN feature_relationship r
    ON r.type_id = (select cvterm_id from cvterm where name = 'orthologous_to')
   AND object.feature_id = r.object_id
  JOIN feature subject
    ON subject.feature_id = r.subject_id AND subject.organism_id = ?
 WHERE object.feature_id in (select feature_id from protein_coding_genes)";

  my $orthologs_query = "
CREATE TEMP TABLE full_table AS
SELECT o_un, s_name
  FROM ortholog_list
 UNION
SELECT uniquename AS o_un, 'NONE'
  FROM protein_coding_genes
 WHERE feature_id NOT IN (select feature_id from ortholog_list)";

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
    $sth->execute($other_organism->organism_id())
      or die "Couldn't execute: " . $sth->errstr;

    $sth = $dbh->prepare($orthologs_query);
    $sth->execute() or die "Couldn't execute: " . $sth->errstr;

    $sth = $dbh->prepare($query);
    $sth->execute() or die "Couldn't execute: " . $sth->errstr;

    iterate {
      my @data = $sth->fetchrow_array();
      if (@data) {
        return [@data];
      } else {
        return undef;
      }
    };
  };
}

method header
{
  return '';
}

method format_result($res)
{
  return join "\t", @$res;
}

1;
