package PomBase::Retrieve::Modifications;

=head1 NAME

PomBase::Retrieve::Modifications - Retrieve modifications in bulk upload format

=head1 SYNOPSIS

See http://www.pombase.org/submit-data/modification-bulk-upload-file-format

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::Modifications

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

use Iterator::Simple qw(iterator);

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';
with 'PomBase::Role::ExtensionDisplayer';

method _get_mod_fcs() {
  my $chado = $self->chado();

  my %feature_cvterms = ();

  my $where = q/feature_cvterm_id in (
select feature_cvterm_id
  from pombase_feature_cvterm_ext_resolved_terms fc
 where base_cv_name = 'PSI-MOD')/;

  my $rs = $chado->resultset('Sequence::FeatureCvterm')->
    search({},
           { prefetch => 'cvterm', where => \$where});

  while (defined (my $fc = $rs->next())) {
    $feature_cvterms{$fc->feature_cvterm_id()} = $fc;
  }

  return %feature_cvterms;
}

method retrieve() {
  my $chado = $self->chado();

  my %feature_cvterms = $self->_get_mod_fcs();

  my $sql = q/
select fc.feature_cvterm_id, gene.uniquename, gene.name, db.name || ':' || x.accession as psimodid,
       evprop.value as evidence, resprop.value as residue,
       pub.uniquename as pmid, dateprop.value as date
  from pombase_feature_cvterm_ext_resolved_terms fc
  join feature transcript on transcript.feature_id = fc.feature_id
  join feature_relationship gene_rel on transcript.feature_id = gene_rel.subject_id
  join feature gene on gene.feature_id = gene_rel.object_id
  join pub on fc.pub_id = pub.pub_id
  join cvterm t on fc.base_cvterm_id = t.cvterm_id
  join dbxref x on x.dbxref_id = t.dbxref_id
  join db on db.db_id = x.db_id
  left outer join feature_cvtermprop evprop on
       fc.feature_cvterm_id = evprop.feature_cvterm_id and
       evprop.type_id in (select cvterm_id from cvterm where name = 'evidence')
  left outer join feature_cvtermprop resprop on
       fc.feature_cvterm_id = resprop.feature_cvterm_id and
       resprop.type_id in (select cvterm_id from cvterm where name = 'residue')
  left outer join feature_cvtermprop dateprop on
       fc.feature_cvterm_id = dateprop.feature_cvterm_id and
       dateprop.type_id in (select cvterm_id from cvterm where name = 'date')
 where base_cv_name = 'PSI-MOD' AND gene.organism_id = / . $self->organism()->organism_id();

  my $dbh = $chado->storage()->dbh();

  my $taxonid = $self->organism_taxonid();

  my $it = do {

    my $sth = $dbh->prepare($sql);
    $sth->execute()
      or die "Couldn't execute query: " . $sth->errstr();

    iterator {
      my ($feature_cvterm_id, $gene_uniquename, $gene_name, $psimodid,
          $evidence, $residue, $pmid, $date) = $sth->fetchrow_array();
      if (defined $feature_cvterm_id) {
        if (!$feature_cvterms{$feature_cvterm_id}) {
          die $feature_cvterm_id;
        }
        my ($extensions) = $self->make_gaf_extension($feature_cvterms{$feature_cvterm_id});
        return [$gene_uniquename, $gene_name // '', $psimodid,
                $evidence // '', $residue // '',
                $extensions // '', $pmid, $taxonid, $date // ''];
    } else {
        return undef;
      }
    };
  };
}

method header {
  return '';
}

method format_result($res) {
  return (join "\t", @$res);
}

1;
