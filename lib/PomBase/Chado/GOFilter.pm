package PomBase::Chado::GOFilter;

=head1 NAME

PomBase::Chado::GOFilter - Code for removing redundant GO annotation

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::GOFilter

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2011 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';

method process()
{
  my $chado = $self->chado();
  my $config = $self->config();

  my $dbh = $chado->storage()->dbh();

  my $go_cvterms_query = <<'EOQ';
CREATE TEMP TABLE go_cvterms AS
SELECT cvterm.* FROM cvterm, cv
WHERE
  cvterm.cv_id = cv.cv_id
AND
  cv.name in ('biological_process', 'cellular_component', 'molecular_function');
EOQ

  my $sth = $dbh->prepare($go_cvterms_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my $poor_ev_query = <<'EOQ';
CREATE TEMP TABLE poor_evidence_fcs AS
SELECT feature_cvterm.* FROM feature_cvterm, feature_cvtermprop prop,
       cvterm prop_type, go_cvterms
WHERE
  feature_cvterm.cvterm_id = go_cvterms.cvterm_id
AND
  feature_cvterm.feature_cvterm_id = prop.feature_cvterm_id
AND
  prop_type.name = 'evidence'
AND
  prop.type_id = prop_type.cvterm_id
AND
  prop.value in ('Inferred from Electronic Annotation',
   'Inferred from Expression Pattern','Non-traceable Author Statement',
   'inferred from Reviewed Computational Analysis',
   'Traceable Author Statement', 'Inferred by Curator')
EOQ

  $sth = $dbh->prepare($poor_ev_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my $poor_ev_index = <<'EOQ';
CREATE INDEX poor_evidence_fsc_id on poor_evidence_fcs(cvterm_id);
EOQ

  $sth = $dbh->prepare($poor_ev_index);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my $fc_to_delete_query = <<'EOQ';
CREATE TEMP TABLE fc_to_delete AS
SELECT feature_cvterm_id
FROM poor_evidence_fcs
WHERE
  poor_evidence_fcs.cvterm_id in (  -- check for child term
    SELECT object_id
      FROM cvtermpath path, feature_cvterm fc2
     WHERE subject_id = fc2.cvterm_id
       AND fc2.feature_id = poor_evidence_fcs.feature_id
       AND pathdistance > 0
    )
OR
  EXISTS ( -- check for annotation with better evidence
    SELECT fc1.feature_cvterm_id
      FROM feature_cvterm fc1
     WHERE fc1.feature_cvterm_id <> poor_evidence_fcs.feature_cvterm_id
       AND fc1.cvterm_id = poor_evidence_fcs.cvterm_id
       AND fc1.feature_id = poor_evidence_fcs.feature_id
       AND fc1.feature_cvterm_id NOT IN (
         SELECT pefcs.feature_cvterm_id
           FROM poor_evidence_fcs pefcs))
OR
  EXISTS ( -- delete all but one poor evidence annotation
    SELECT fc1.feature_cvterm_id
      FROM feature_cvterm fc1
     WHERE fc1.feature_cvterm_id > poor_evidence_fcs.feature_cvterm_id
       AND fc1.cvterm_id = poor_evidence_fcs.cvterm_id
       AND fc1.feature_id = poor_evidence_fcs.feature_id);
EOQ

  $sth = $dbh->prepare($fc_to_delete_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my $delete_query = <<'EOD';
delete from feature_cvterm
  where feature_cvterm.feature_cvterm_id in (select * from fc_to_delete);
EOD

  $sth = $dbh->prepare($delete_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;
}

1;
