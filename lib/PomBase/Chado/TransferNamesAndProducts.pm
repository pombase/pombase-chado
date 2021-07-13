package PomBase::Chado::TransferNamesAndProducts;

=head1 NAME

PomBase::Import::TransferNamesAndProducts - transfer name and product from
    org A to org B using one-to-one orthologs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::TransferNamesAndProducts

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
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has source_organism => (is => 'rw', init_arg => undef);
has dest_organism => (is => 'rw', init_arg => undef);

with 'PomBase::Role::OrthologMap';

has existing_names => (is => 'rw', init_arg => undef);
has existing_products => (is => 'rw', init_arg => undef);

sub BUILD
{
  my $self = shift;

  my $source_organism_taxonid = undef;
  my $dest_organism_taxonid = undef;

  my @opt_config = ("source-organism-taxonid=s" => \$source_organism_taxonid,
                    "dest-organism-taxonid=s" => \$dest_organism_taxonid,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $source_organism_taxonid || length $source_organism_taxonid == 0) {
    die "no --source-organism-taxonid passed to the TransferNamesAndProducts loader\n";
  }

  my $source_organism = $self->find_organism_by_taxonid($source_organism_taxonid);

  if (!defined $source_organism) {
    die "can't find organism with taxon ID: $source_organism_taxonid\n";
  }

  $self->source_organism($source_organism);


  if (!defined $dest_organism_taxonid || length $dest_organism_taxonid == 0) {
    die "no --dest-organism-taxonid passed to the TransferNamesAndProducts loader\n";
  }

  my $dest_organism = $self->find_organism_by_taxonid($dest_organism_taxonid);

  if (!defined $dest_organism) {
    die "can't find organism with taxon ID: $dest_organism_taxonid\n";
  }

  $self->dest_organism($dest_organism);


  my %existing_products = ();

  my $product_cv_name = 'PomBase gene products';

  my $chado_dbh = $self->chado()->storage()->dbh();
  my $sth = $chado_dbh->prepare(<<'EOF');
SELECT f.uniquename, transcript.feature_id, product_cvterm.cvterm_id, fc.pub_id
FROM feature f
JOIN organism ON f.organism_id = organism.organism_id
JOIN cvterm feature_type ON feature_type.cvterm_id = f.type_id
JOIN feature_relationship feature_rel ON feature_rel.object_id = f.feature_id
JOIN cvterm rel_type ON rel_type.cvterm_id = feature_rel.type_id
JOIN feature transcript ON transcript.feature_id = feature_rel.subject_id
LEFT OUTER JOIN feature_cvterm fc ON fc.feature_id = transcript.feature_id
LEFT OUTER JOIN cvterm product_cvterm ON product_cvterm.cvterm_id = fc.cvterm_id AND
                product_cvterm.cv_id IN (SELECT cv_id from cv where cv.name = ?)
WHERE ( ( organism.organism_id = ? OR organism.organism_id = ? )
        AND feature_type.name = 'gene'
        AND rel_type.name = 'part_of');
EOF

  $sth->execute($product_cv_name, $source_organism->organism_id(), $dest_organism->organism_id());

  while (my ($gene_uniquename, $transcript_feature_id, $product_cvterm_id, $feature_cvterm_pub_id) =
           $sth->fetchrow_array()) {
    $existing_products{$gene_uniquename}->{transcript_feature_id} = $transcript_feature_id;
    if (defined $product_cvterm_id) {
      $existing_products{$gene_uniquename}->{product_cvterm_id} = $product_cvterm_id;
      $existing_products{$gene_uniquename}->{feature_cvterm_pub_id} = $feature_cvterm_pub_id;
    };
  }

  $self->existing_products(\%existing_products);
}


sub process {
  my $self = shift;
  my $fh = shift;

  my %orthologs = $self->ortholog_map($self->source_organism(),
                                      $self->dest_organism());

  my $gene_rs = $self->chado()->resultset('Sequence::Feature')
    ->search(
      {
        organism_id => $self->dest_organism()->organism_id(),
        'type.name' => 'gene',
      },
      {
        join => 'type',
      });

  my $name_update_count = 0;
  my $product_update_count = 0;

  while (defined (my $gene = $gene_rs->next())) {
    my $orth_detail = $orthologs{$gene->uniquename()};

    next unless $orth_detail;

    if (!$gene->name()) {
      if ($orth_detail) {
        my $orth_name = $orth_detail->{orth_name};

        if ($orth_name) {
          $gene->name($orth_name);
          $gene->update();
          $name_update_count++;
        }
      }
    }

    my $existing_product_detail = $self->existing_products()->{$gene->uniquename()};

    if ($existing_product_detail) {
      if (!$existing_product_detail->{product_cvterm_id}) {
        my $orth_product_details =
          $self->existing_products()->{$orth_detail->{orth_uniquename}};

        if ($orth_product_details->{product_cvterm_id}) {
          $self->chado()->resultset("Sequence::FeatureCvterm")
            ->create({
              feature_id => $existing_product_detail->{transcript_feature_id},
              cvterm_id => $orth_product_details->{product_cvterm_id},
              pub_id => $orth_product_details->{feature_cvterm_pub_id},
            });
          $product_update_count++;
        }
      }
    }
  }

  warn "transferred $name_update_count names and $product_update_count products\n";
}

1;
