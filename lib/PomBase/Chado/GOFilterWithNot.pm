package PomBase::Chado::GOFilterWithNot;

=head1 NAME

PomBase::Chado::GOFilterWithNot - Remove inferred annotations with there is
    a non-inferred NOT annotation

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::GOFilterWithNot

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;
use Moose;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';

sub process {
  my $self = shift;

  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $deletion_query = <<'EOQ';
WITH
 not_fc AS
  (SELECT fc.feature_id,
          fc.cvterm_id
   FROM feature_cvterm fc
   JOIN feature_cvtermprop fcp ON fc.feature_cvterm_id = fcp.feature_cvterm_id
   JOIN cvterm fcpt ON fcp.type_id = fcpt.cvterm_id
   WHERE is_not
     AND fcpt.name = 'evidence'
     AND fcp.value <> 'Inferred from Electronic Annotation'),

 inferred_fc AS
  (SELECT fc.feature_cvterm_id,
          fc.feature_id,
          fc.cvterm_id
   FROM feature_cvterm fc
   JOIN feature_cvtermprop fcp ON fc.feature_cvterm_id = fcp.feature_cvterm_id
   JOIN cvterm fcpt ON fcp.type_id = fcpt.cvterm_id
   WHERE NOT is_not
     AND fcpt.name = 'evidence'
     AND fcp.value = 'Inferred from Electronic Annotation')
     DELETE from feature_cvterm where feature_cvterm_id in
     (
SELECT inferred_fc.feature_cvterm_id
FROM inferred_fc
JOIN cvtermpath ON inferred_fc.cvterm_id = cvtermpath.subject_id
JOIN cvterm pathtype ON cvtermpath.type_id = pathtype.cvterm_id
JOIN not_fc ON cvtermpath.object_id = not_fc.cvterm_id
AND inferred_fc.feature_id = not_fc.feature_id
WHERE pathtype.name = 'is_a'
UNION
SELECT inferred_fc.feature_cvterm_id
FROM inferred_fc
JOIN not_fc ON inferred_fc.cvterm_id = not_fc.cvterm_id
AND inferred_fc.feature_id = not_fc.feature_id);
EOQ

  my $sth = $dbh->prepare($deletion_query);
  $sth->execute() or die "Couldn't execute deletion query: " . $sth->errstr;
}

1;

