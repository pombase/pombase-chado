package PomBase::Chado::UniProtIDsToLocal;

=head1 NAME

PomBase::Chado::UniProtIDsToLocal - Change any "UniProtKB:" IDs from loading to
                                    local (PomBase) IDs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::UniProtIDsToLocal

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';


=head2 process

 Usage : my $filter = PomBase::Chado::UniProtIDsToLocal->new(config => $config,
                                                             chado => $chado);
         $filter->process();
 Func  : Change "UniProtKB:" ids in feature_cvtermprop 'with' rows to a PomBase:
         ID, where one is available.  The uniprot_identifier featureprops are
         used to do the mapping.
 Args  : $config - a Config object
         $chado - a schema object of the Chado database
 Return: nothing, dies on error

=cut

method process()
{
  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $change_uniprot_ids = <<'EOQ';
UPDATE feature_cvtermprop fcp
   SET value = 'PomBase:' || f.uniquename
  FROM featureprop fp
  JOIN feature f ON fp.feature_id = f.feature_id
 WHERE fp.type_id in
      (SELECT cvterm_id FROM cvterm WHERE name = 'uniprot_identifier')
   AND fcp.value = 'UniProtKB:' || fp.value;
EOQ

  my $sth = $dbh->prepare($change_uniprot_ids);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;
}
