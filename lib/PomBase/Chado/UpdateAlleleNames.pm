package PomBase::Chado::UpdateAlleleNames;

=head1 NAME

PomBase::Chado::UpdateAlleleNames - Update old allele name

=head1 DESCRIPTION

This code updates allele names that our now out of date.

Currently:
  "SPAC1234c.12delta" to "abcdelta" if SPAC1234c.12 now has a gene name

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::UpdateAlleleNames

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';

=head2 process

 Usage : my $filter = PomBase::Chado::UpdateAlleleNames->new(config => $config,
                                                             chado => $chado);
           $filter->process();
 Func  : Update gene names that are out of date.  eg. change
          "SPAC1234c.12delta" to "abcdelta" if SPAC1234c.12 now has a gene name
 Args  : $config - a Config object
         $chado - a schema object of the Chado database
 Return: nothing, dies on error

=cut

method process()
{
  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $update_allele_names = <<'EOQ';
UPDATE feature allele SET name = gene.name || 'delta'
  FROM feature_relationship rel, feature gene, cvterm rel_type,
       cvterm allele_type
 WHERE rel_type.name = 'instance_of' AND
       gene.name IS NOT NULL AND allele.name LIKE gene.uniquename || 'delta' AND
       allele.feature_id = rel.subject_id AND
       gene.feature_id = rel.object_id AND rel.type_id = rel_type.cvterm_id AND
       allele_type.cvterm_id = allele.type_id AND allele_type.name = 'allele'
EOQ

  my $sth = $dbh->prepare($update_allele_names);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;
}

1;
