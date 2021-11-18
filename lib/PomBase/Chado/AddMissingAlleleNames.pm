package PomBase::Chado::AddMissingAlleleNames;

=head1 NAME

PomBase::Chado::AddMissingAlleleNames - Auto-generate allele names where
   possible by using the description and gene name

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::AddMissingAlleleNames

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

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';

with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');

sub BUILD
{

}

sub check_description
{
  my $allele_type = shift;
  my $description = shift;

  map {
    if (($allele_type eq 'nucleotide_mutation' &&
         !(/^-?([ATGCU]+)\d+([ATGCU]+)$/ && length $1 == length $2)) ||
        ($allele_type eq 'amino_acid_mutation' &&
         !(/^-?([A-Z]+)\d+([A-Z]+)$/ && length $1 == length $2))) {
      return 0;
    }
  } split ',', $description;

  return 1;
}

sub process
{
  my $self = shift;

  my $sql = <<'EOQ';
SELECT allele.feature_id as allele_feature_id,
       allele_type_prop.value as allele_type,
       desc_prop.value as description,
       gene.name as gene_name,
       array_to_string(array(
         SELECT value
           FROM featureprop sess_p
          WHERE sess_p.type_id in
             (SELECT cvterm_id
              FROM cvterm
              WHERE name = 'canto_session')
           AND sess_p.feature_id = allele.feature_id), ',') as session
FROM feature allele
JOIN featureprop desc_prop ON desc_prop.feature_id = allele.feature_id
JOIN cvterm desc_prop_type ON desc_prop_type.cvterm_id = desc_prop.type_id
JOIN featureprop allele_type_prop ON allele_type_prop.feature_id = allele.feature_id
JOIN cvterm allele_type_prop_type ON allele_type_prop_type.cvterm_id = allele_type_prop.type_id
JOIN feature_relationship rel ON rel.subject_id = allele.feature_id
JOIN feature gene ON rel.object_id = gene.feature_id
JOIN cvterm rel_type ON rel_type.cvterm_id = rel.type_id
WHERE allele_type_prop.value in ('amino_acid_mutation', 'nucleotide_mutation')
  AND allele_type_prop_type.name = 'allele_type'
  AND allele.name IS NULL
  AND gene.name IS NOT NULL
  AND desc_prop_type.name = 'description';
EOQ

  my $dbh = $self->chado()->storage()->dbh();

  my $sth = $dbh->prepare($sql);
  $sth->execute();

  my @warnings = ();

  while (my ($allele_feature_id, $allele_type, $allele_description, $gene_name,
             $session, $source) = $sth->fetchrow_array()) {

    if (check_description($allele_type, $allele_description)) {
      my $allele_name = "$gene_name-$allele_description";
      my $update_sth = $dbh->prepare("UPDATE feature SET name = ? WHERE feature_id = ?");
      $update_sth->execute($allele_name, $allele_feature_id);
    } else {
      push @warnings,
        "$allele_type  $gene_name       $allele_description    $session";
    }
  }

  if (@warnings) {
    print "some alleles could not be automatically named:\n\n";
    print "alelle type          gene name  allele description   session (if available)\n";
    map { print "$_\n"; } @warnings;
  }
}

1;
