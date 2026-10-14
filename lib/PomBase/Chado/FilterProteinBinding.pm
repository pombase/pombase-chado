package PomBase::Chado::FilterProteinBinding;

=head1 NAME

PomBase::Chado::FilterProteinBinding - Remove protein binding GO annotations
  where there is a physical interaction with the same two genes

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr@pombase.org> >>

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2026 Kim Rutherford, all rights reserved.

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

sub _make_interaction_table
{
  my $self = shift;

  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $query = <<'EOQ';
CREATE TEMP TABLE physical_interactions AS
SELECT subj.uniquename as gene1, pub.uniquename AS pub_uniquename, 'PomBase:' || obj.uniquename as gene2
FROM feature_relationship rel
JOIN feature_relationship_pub rel_pub on rel_pub.feature_relationship_id = rel.feature_relationship_id
JOIN pub ON rel_pub.pub_id = pub.pub_id
JOIN cvterm TYPE ON type.cvterm_id = rel.type_id
JOIN feature subj ON subj.feature_id = rel.subject_id
JOIN feature obj ON obj.feature_id = rel.object_id
WHERE type.name = 'interacts_physically'
UNION
SELECT obj.uniquename as gene1, pub.uniquename AS pub_uniquename, 'PomBase:' || subj.uniquename as gene2
FROM feature_relationship rel
JOIN feature_relationship_pub rel_pub on rel_pub.feature_relationship_id = rel.feature_relationship_id
JOIN pub ON rel_pub.pub_id = pub.pub_id
JOIN cvterm TYPE ON type.cvterm_id = rel.type_id
JOIN feature subj ON subj.feature_id = rel.subject_id
JOIN feature obj ON obj.feature_id = rel.object_id
WHERE type.name = 'interacts_physically';
EOQ

  my $sth = $dbh->prepare($query);
  $sth->execute();
}

sub process {
  my $self = shift;

  $self->_make_interaction_table();

  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $query = <<'EOQ';
WITH
bindings AS
  (SELECT fc.feature_cvterm_id, gene.uniquename AS gene, pub.uniquename AS pub_uniquename, p.value AS with_gene
   FROM feature_cvterm fc
   JOIN pub ON fc.pub_id = pub.pub_id
   JOIN feature_cvtermprop p ON p.feature_cvterm_id = fc.feature_cvterm_id
   JOIN cvterm pt ON p.type_id = pt.cvterm_id
   JOIN feature transcript ON transcript.feature_id = fc.feature_id
   JOIN feature_relationship rel ON rel.subject_id = transcript.feature_id
   JOIN cvterm rel_type ON rel_type.cvterm_id = rel.type_id
   JOIN feature gene ON gene.feature_id = rel.object_id
   JOIN cvterm gene_type ON gene_type.cvterm_id = gene.type_id
   JOIN cvterm t ON t.cvterm_id = fc.cvterm_id
   WHERE t.name = 'protein binding'
     AND pt.name = 'with'
     AND rel_type.name = 'part_of'
     AND gene_type.name = 'gene'
     AND fc.feature_cvterm_id NOT IN
       (SELECT feature_cvterm_id FROM feature_cvtermprop
        WHERE type_id IN (SELECT cvterm_id FROM cvterm WHERE name = 'residue'))),
     annotation_to_delete AS
  (SELECT feature_cvterm_id
   FROM bindings
   JOIN physical_interactions interaction ON bindings.gene = interaction.gene1
     AND bindings.with_gene = interaction.gene2
     AND bindings.pub_uniquename = interaction.pub_uniquename)
DELETE
FROM feature_cvterm
WHERE feature_cvterm_id IN
    (SELECT feature_cvterm_id
     FROM annotation_to_delete);
EOQ

  my $sth = $dbh->prepare($query);
  $sth->execute();
}

1;
