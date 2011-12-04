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

with 'PomBase::Retriever';
with 'PomBase::Role::CvQuery';

method retrieve() {
  my $chado = $self->chado();

  my $dbh = $self->chado()->storage()->dbh();

  my $protein_temp = "
CREATE TEMP TABLE protein_coding_genes AS
SELECT object_id
FROM feature_relationship r, cvterm rt, feature s, cvterm st
WHERE r.subject_id = s.feature_id
  AND r.type_id = rt.cvterm_id
  AND s.type_id = st.cvterm_id
  AND st.name = 'mRNA';";

  my $ortholog_temp = "
CREATE TEMP TABLE ortholog_list AS
SELECT object.uniquename as o_un, subject.name as s_name
FROM feature_relationship me
JOIN feature subject ON subject.feature_id = me.subject_id
JOIN feature object ON object.feature_id = me.object_id
WHERE me.type_id = (select cvterm_id from cvterm where name = 'orthologous_to')
  AND subject.organism_id = (select organism_id from organism where common_name = 'Scerevisiae')
  AND object.feature_id in (select * from protein_coding_genes)
UNION
SELECT uniquename as o_un, 'NONE' as s_name
 FROM feature f where f.feature_id not in
      (select object_id from feature_relationship r, feature subject_f
        WHERE r.subject_id = subject_f.feature_id
          AND subject_f.organism_id = (select organism_id from organism where
        common_name = 'Scerevisiae'))
  AND f.organism_id = (select organism_id from organism where
        common_name = 'pombe')
  AND f.type_id = (select cvterm_id from cvterm where name = 'gene')
  AND f.feature_id in (select * from protein_coding_genes)
 ORDER BY o_un, s_name;";

  my $query = "
SELECT o_un, string_agg(s_name, '|')
FROM ortholog_list
GROUP BY o_un
 ORDER BY o_un;";

  my $it = do {
    my $sth = $dbh->prepare($protein_temp);
    $sth->execute() or die "Couldn't execute: " . $sth->errstr;

    $sth = $dbh->prepare($ortholog_temp);
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
