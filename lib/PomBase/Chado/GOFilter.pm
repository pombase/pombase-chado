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

method filter($fh)
{
  my $chado = $self->chado();
  my $config = $self->config();

  my $dbh = $chado->storage()->dbh();

  my $query = <<'EOQ';
create temp table fc_to_delete
AS
  SELECT fc1.feature_cvterm_id
from feature_cvterm fc1, cvterm c1, cv, feature_cvtermprop fc1_prop, cvterm fc1_type, cvterm prop_type
where
  fc1_prop.type_id = prop_type.cvterm_id
and
  prop_type.name = 'evidence'
and
  fc1.cvterm_id = fc1_type.cvterm_id
and
  fc1_prop.value in
  ('Inferred from Electronic Annotation',
  'Inferred from Expression Pattern',
  'Non-traceable Author Statement',
  'inferred from Reviewed Computational Analysis')
and
  fc1_prop.feature_cvterm_id = fc1.feature_cvterm_id
and
  fc1.cvterm_id = c1.cvterm_id
and
  c1.cv_id = cv.cv_id
and
  cv.name in ('biological_process', 'cellular_component', 'molecular_function')
and
  fc1.cvterm_id in (select object_id from cvtermpath path
    where subject_id in
     (select fc2.cvterm_id
      from feature_cvterm fc2
      where fc2.feature_id = fc1.feature_id
     ) and pathdistance > 0
     );
EOQ

  my $sth = $dbh->prepare($query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my $delete_query = <<'EOD';
delete from feature_cvterm
  where feature_cvterm.feature_cvterm_id in (select * from fc_to_delete);
EOD

  $sth = $dbh->prepare($delete_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;
}

1;
