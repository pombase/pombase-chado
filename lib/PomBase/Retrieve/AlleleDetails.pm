package PomBase::Retrieve::AlleleDetails;

=head1 NAME

PomBase::Retrieve::AlleleDetails - Export all allele IDs, names, descriptions,
      types and gene IDs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::AlleleDetails

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2022 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose;

use Iterator::Simple qw(iterator);

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';

sub retrieve {
  my $self = shift;

  my $chado = $self->chado();

  my $sql = q|
SELECT gene.uniquename AS gene_uniquename,
       gene.name AS gene_name,
       allele.uniquename AS allele_uniquename,
       allele.name AS allele_name, desc_prop.value AS allele_description,
       type_prop.value AS allele_type,
       array_to_string(array(SELECT DISTINCT pub.uniquename
                               FROM feature_pub fp
                               JOIN pub on pub.pub_id = fp.pub_id
                              WHERE fp.feature_id = allele.feature_id), ',') AS references
FROM feature allele
JOIN cvterm allele_type_cvterm ON allele_type_cvterm.cvterm_id = allele.type_id
JOIN feature_relationship rel ON rel.subject_id = allele.feature_id
JOIN feature gene ON rel.object_id = gene.feature_id
JOIN cvterm gene_type_cvterm ON gene_type_cvterm.cvterm_id = gene.type_id
LEFT OUTER JOIN featureprop desc_prop ON desc_prop.feature_id = allele.feature_id
AND desc_prop.type_id in (SELECT cvterm_id FROM cvterm WHERE name = 'description')
LEFT OUTER JOIN featureprop type_prop ON type_prop.feature_id = allele.feature_id
AND type_prop.type_id in (SELECT cvterm_id FROM cvterm WHERE name = 'allele_type')
WHERE allele_type_cvterm.name = 'allele'
  AND gene_type_cvterm.name = 'gene'
  AND gene.organism_id = | . $self->organism()->organism_id();

  my $dbh = $chado->storage()->dbh();

  my $it = do {

    my $sth = $dbh->prepare($sql);
    $sth->execute()
      or die "Couldn't execute query: " . $sth->errstr();

    iterator {
      my @data = $sth->fetchrow_array();
      if (@data) {
        map {
          $_ = '' unless defined;
        } @data;
        return [@data];
      } else {
        return undef;
      }
    };
  };
}

sub header {
  my $self = shift;
  return (join "\t",
    qw(gene_uniquename gene_name allele_uniquename allele_name allele_description allele_type references)) . "\n";
}

sub format_result {
  my $self = shift;
  my $res = shift;

  return (join "\t", @$res);
}


1;
