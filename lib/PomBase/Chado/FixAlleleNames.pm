package PomBase::Chado::FixAlleleNames;

=head1 NAME

PomBase::Chado::FixAlleleNames - if name and description are the same
   and look like a residue change (eg. "A123K" or "K21A,T23A"), add the gene
   name as a prefix to the allele name: "abc1-A123K" "abc1-K21A,T23A"

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::FixAlleleNames

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


=head2

 Usage   : if (allele_name_needs_gene_name($allele_name, $allele_type)) { ... }
 Function: return 1 if the allele name looks look a description for the
           given $allele_type (like "A123D" for amino_acid_mutation)
 Args    : $allele_name
           $allele_description

=cut

sub allele_name_needs_gene_name
{
  my $name = shift;
  my $allele_type = shift;

  if ($name =~ /^[A-Z]+\d+[A-Z]+(?:,?[A-Z]+\d+[A-Z]+)*$/) {
    return 1;
  }

  if ($allele_type eq 'partial_amino_acid_deletion' &&
      $name =~ /^\d+-\d+$/) {
    return 1;
  }

  if ($allele_type eq 'amino_acid_mutation' &&
      $name =~ /^[A-Z]\d+/) {
    return 1;
  }

  if ($allele_type eq 'nonsense_mutation' &&
      $name =~ /^[A-Z]\d+->stop$/) {
    return 1;
  }

  return 0;
}

sub process
{
  my $self = shift;

  my $sql = <<'EOQ';
SELECT gene.name, allele.feature_id, allele.name, type_p.value as allele_type,
       array_to_string(array(
         SELECT distinct value
           FROM featureprop sess_p
          WHERE sess_p.type_id in
             (SELECT cvterm_id
              FROM cvterm
              WHERE name = 'canto_session')
           AND sess_p.feature_id = allele.feature_id), ',') as session
FROM feature allele
JOIN featureprop type_p ON type_p.feature_id = allele.feature_id
JOIN featureprop desc_p ON desc_p.feature_id = allele.feature_id
JOIN cvterm desc_p_type ON desc_p.type_id = desc_p_type.cvterm_id
JOIN feature_relationship rel on allele.feature_id = rel.subject_id
JOIN feature gene on rel.object_id = gene.feature_id
JOIN cvterm rel_type on rel.type_id = rel_type.cvterm_id
WHERE type_p.type_id in
    (SELECT cvterm_id
     FROM cvterm
     WHERE name = 'allele_type')
  AND allele.name = desc_p.value
  AND type_p.value <> 'other'
  AND type_p.value <> 'disruption'
  AND rel_type.name = 'instance_of';
EOQ

  my $dbh = $self->chado()->storage()->dbh();

  my @warnings = ();

  my $sth = $dbh->prepare($sql);
  $sth->execute();

  my $update_sth = $dbh->prepare("UPDATE feature SET name = ? WHERE feature_id = ?");

  while (my ($gene_name, $allele_feature_id, $allele_name, $allele_type, $session) = $sth->fetchrow_array()) {
    if (defined $gene_name &&
        allele_name_needs_gene_name($allele_name, $allele_type)) {
      my $new_allele_name = "$gene_name-$allele_name";
      $update_sth->execute($new_allele_name, $allele_feature_id);
    } else {
      $gene_name //= '[unnamed]';
      push @warnings, "$gene_name\t$allele_name\t$session";
    }
  }

  if (@warnings) {
    print "some alleles have name and description the same but couldn't have the gene name added automatically as a prefix:\n\n";
    print "gene_name\tallele_name+desc\tsession\n";
    map { print "$_\n"; } @warnings;
  }
}

1;
