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

method process_one_evidence_code($code) {
  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $go_cvterms_query = <<'EOQ';
CREATE TEMP TABLE go_cvterms AS
SELECT t.* FROM cvterm t
  JOIN pombase_feature_cvterm_ext_resolved_terms res ON t.cvterm_id = res.cvterm_id
  JOIN feature_cvterm base_fc on res.feature_cvterm_id = base_fc.feature_cvterm_id
 WHERE res.base_cv_name IN ('biological_process', 'cellular_component', 'molecular_function')
   AND NOT base_fc.is_not;

CREATE INDEX go_cvterms_cvterm_id_idx on go_cvterms(cvterm_id);
EOQ

  my $sth = $dbh->prepare($go_cvterms_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my $poor_ev_query = <<"EOQ";
CREATE TEMP TABLE poor_evidence_fcs AS
SELECT feature_cvterm.* FROM feature_cvterm, feature_cvtermprop prop,
       cvterm prop_type
WHERE
  feature_cvterm.cvterm_id in (select cvterm_id from go_cvterms)
AND
  feature_cvterm.feature_cvterm_id = prop.feature_cvterm_id
AND
  prop_type.name = 'evidence'
AND
  prop.type_id = prop_type.cvterm_id
AND
  NOT feature_cvterm.is_not
AND
  lower(prop.value) = '$code'
EOQ

  $sth = $dbh->prepare($poor_ev_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my $poor_ev_index = <<'EOQ';
CREATE INDEX poor_evidence_fsc_id on poor_evidence_fcs(cvterm_id);
DROP table go_cvterms;
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
       AND NOT fc2.is_not
       AND pathdistance > 0
    )
OR  -- check for child term + extension via cvtermpath
  poor_evidence_fcs.cvterm_id in (
    SELECT path.object_id
      FROM cvtermpath path, feature_cvterm fc2, cvterm extension_term,
           cvterm_relationship extension_rel
     WHERE extension_term.cvterm_id = fc2.cvterm_id
       AND extension_term.cvterm_id = extension_rel.subject_id
       AND extension_rel.type_id =
           (select cvterm_id from cvterm where name = 'is_a')
       AND fc2.feature_id = poor_evidence_fcs.feature_id
       AND NOT fc2.is_not
       AND path.subject_id = extension_rel.object_id
       AND pathdistance > 0
    )
OR  -- check for child term + extension with direct parent
  poor_evidence_fcs.cvterm_id in (
    SELECT extension_rel.object_id
      FROM feature_cvterm fc2, cvterm extension_term,
           cvterm_relationship extension_rel
     WHERE extension_term.cvterm_id = fc2.cvterm_id
       AND extension_term.cvterm_id = extension_rel.subject_id
       AND NOT fc2.is_not
       AND extension_rel.type_id =
           (select cvterm_id from cvterm where name = 'is_a')
       AND fc2.feature_id = poor_evidence_fcs.feature_id
    )
OR
  EXISTS ( -- check for annotation with better evidence
    SELECT fc1.feature_cvterm_id
      FROM feature_cvterm fc1
     WHERE fc1.feature_cvterm_id <> poor_evidence_fcs.feature_cvterm_id
       AND fc1.cvterm_id = poor_evidence_fcs.cvterm_id
       AND fc1.feature_id = poor_evidence_fcs.feature_id
       AND NOT fc1.is_not
       AND fc1.feature_cvterm_id NOT IN (
         SELECT pefcs.feature_cvterm_id
           FROM poor_evidence_fcs pefcs))
OR
  EXISTS ( -- delete all but one poor evidence annotation
    SELECT fc1.feature_cvterm_id
      FROM feature_cvterm fc1
     WHERE fc1.feature_cvterm_id > poor_evidence_fcs.feature_cvterm_id
       AND NOT fc1.is_not
       AND fc1.cvterm_id = poor_evidence_fcs.cvterm_id
       AND fc1.feature_id = poor_evidence_fcs.feature_id);

DROP TABLE poor_evidence_fcs;
EOQ

  $sth = $dbh->prepare($fc_to_delete_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my $delete_query = <<'EOD';
DELETE FROM feature_cvterm
  WHERE feature_cvterm.feature_cvterm_id IN (SELECT * FROM fc_to_delete);
DROP TABLE fc_to_delete;
EOD

  $sth = $dbh->prepare($delete_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;
}

=head2 process

 Usage   : my $filter = PomBase::Chado::GOFilter->new(config => $config,
                                                      chado => $chado);
           $filter->process();
 Function: Remove redundant GO annotation by removing feature_cvterms where
           there is a more specific annotation or an annotation with a better
           evidence code.
 Args    : $chado - a schema object of the Chado database
 Return  : nothing, dies on error

=cut

method process() {
  my @codes = (
    'inferred from biological aspect of descendant',
    'inferred from biological aspect of ancestor',
    'inferred from electronic annotation',
    'non-traceable author statement',
    'traceable author statement',
    'inferred from sequence model',
    'inferred from sequence or structural similarity',
    'inferred from sequence orthology',
#    'inferred from expression pattern',
#    'inferred from reviewed computational analysis',
    'inferred by curator',
  );

  for my $code (@codes) {
    $self->process_one_evidence_code($code);
  }
}

1;
