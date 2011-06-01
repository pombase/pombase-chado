package PomBase::Chado::LoadOrganism;

=head1 NAME

PomBase::Chado::LoadOrganism - Load organisms into Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::LoadOrganism

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

with 'PomBase::Role::ChadoUser';

method load_organism($genus, $species, $common_name, $abbreviation, $taxon_id)
{
  my $org_prop_types_cv =
    $self->chado()->resultset('Cv::Cv')->find_or_create({
      name => 'pombase_organism_propeties_types',
    });

  my $pombase_db =
    $self->chado()->resultset('General::Db')->find_or_create({
      name => 'PomBase'
    });

  my $taxon_id_dbxref =
    $self->chado()->resultset('General::Dbxref')->find_or_create({
      accession => 'NCBI Taxonomy id',
      db_id => $pombase_db->db_id(),
    });

  my $taxon_id_cvterm =
    $self->chado()->resultset('Cv::Cvterm')->find_or_create({
      cv_id => $org_prop_types_cv->cv_id(),
      dbxref_id => $taxon_id_dbxref->dbxref_id(),
      name => 'taxon_id',
    });

  my $organism =
    $self->chado()->resultset('Organism::Organism')->create({
      genus => $genus,
      species => $species,
      common_name => $common_name,
      abbreviation => $abbreviation,
      organismprops =>
        [ { value => $taxon_id,
            type_id => $taxon_id_cvterm->cvterm_id() } ] });
}

1;
