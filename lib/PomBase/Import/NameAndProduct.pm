package PomBase::Import::NameAndProduct;

=head1 NAME

PomBase::Import::NameAndProduct - feature names and products from a TSV file, but
    don't replace existing names and products

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::NameAndProduct

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

use Try::Tiny;

use Moose;

use Text::CSV;
use Text::Trim qw(trim);

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has dest_organism => (is => 'rw', init_arg => undef);
has existing_products => (is => 'rw', init_arg => undef);

sub BUILD {
  my $self = shift;

  my $dest_organism_taxonid = undef;

  my @opt_config = ("dest-organism-taxonid=s" => \$dest_organism_taxonid,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

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
SELECT f.uniquename, transcript.feature_id, product_cvterm.cvterm_id
FROM feature f
JOIN organism ON f.organism_id = organism.organism_id
JOIN cvterm feature_type ON feature_type.cvterm_id = f.type_id
JOIN feature_relationship feature_rel ON feature_rel.object_id = f.feature_id
JOIN cvterm rel_type ON rel_type.cvterm_id = feature_rel.type_id
JOIN feature transcript ON transcript.feature_id = feature_rel.subject_id
LEFT OUTER JOIN feature_cvterm fc ON fc.feature_id = transcript.feature_id
LEFT OUTER JOIN cvterm product_cvterm ON product_cvterm.cvterm_id = fc.cvterm_id AND
                product_cvterm.cv_id IN (SELECT cv_id from cv where cv.name = ?)
WHERE ( organism.organism_id = ?
        AND feature_type.name = 'gene'
        AND rel_type.name = 'part_of');
EOF

  $sth->execute($product_cv_name, $dest_organism->organism_id());


  while (my ($gene_uniquename, $transcript_feature_id, $product_cvterm_id) =
         $sth->fetchrow_array()) {
    $existing_products{$gene_uniquename}->{transcript_feature_id} = $transcript_feature_id;
    if ($product_cvterm_id) {
      $existing_products{$gene_uniquename}->{product_cvterm_id} = $product_cvterm_id;
    };
  }

  $self->existing_products(\%existing_products);
}


sub load {
  my $self = shift;
  my $fh = shift;

  my $null_pub = $self->find_or_create_pub('null');

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
  my $new_synonym_count = 0;

  my %genes = ();

  while (defined (my $gene = $gene_rs->next())) {
    $genes{$gene->uniquename()} = $gene;
  }

  my $chado_dbh = $self->chado()->storage()->dbh();
  my $sth = $chado_dbh->prepare(<<'EOQ');
SELECT f.uniquename, synonym.name
 FROM feature f
 JOIN organism ON f.organism_id = organism.organism_id
 JOIN cvterm ft ON ft.cvterm_id = f.type_id
 JOIN feature_synonym fs ON fs.feature_id = f.feature_id
 JOIN synonym ON fs.synonym_id = synonym.synonym_id
WHERE ( organism.organism_id = ? AND ft.name = 'gene');
EOQ

  $sth->execute($self->dest_organism()->organism_id());

  my %existing_synonyms = ();

  while (my ($gene_uniquename, $synonym_name) = $sth->fetchrow_array()) {
    push @{$existing_synonyms{$gene_uniquename}}, $synonym_name;
  }

  my $tsv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  while (my $columns_ref = $tsv->getline($fh)) {
    if ($columns_ref->[0] =~ /^#/) {
      next;
    }

    my $gene_uniquename = trim($columns_ref->[0]);
    my $new_name = trim($columns_ref->[1]);
    my $synonyms = trim($columns_ref->[2]);
    my $new_product = trim($columns_ref->[3]);

    my $gene = $genes{$gene_uniquename};

    if ($gene) {
      if (!$gene->name() && $new_name) {
        $gene->name($new_name);
        $name_update_count++;
        $gene->update();
      }

      if (length $synonyms > 0) {
        my @new_synonyms = split /\s*,\s*/, $synonyms;

        my $existing_synonyms = $existing_synonyms{$gene_uniquename} // [];

        map {
          my $new_synonym = $_;

          if (!grep { $_ eq $new_synonym } @$existing_synonyms) {
            $self->store_feature_synonym($gene, $new_synonym, 'exact', 1, undef);
            $new_synonym_count++;
          }
        } @new_synonyms;
      }

     my $existing_product_detail = $self->existing_products()->{$gene_uniquename};

      if ($existing_product_detail) {
        # the detail helpfully includes the transcript_feature_id so we don't need
        # to look it up help

        my $existing_product_detail = $self->existing_products()->{$gene->uniquename()};

        if ($existing_product_detail) {
          # the detail helpfully includes the transcript_feature_id so we don't need
          # to look it up help

          if (!$existing_product_detail->{product_cvterm_id} && $new_product) {
            my $product_cvterm =
              $self->find_or_create_cvterm('PomBase gene products', $new_product);

            $self->chado()->resultset("Sequence::FeatureCvterm")
              ->create({
                feature_id => $existing_product_detail->{transcript_feature_id},
                cvterm_id => $product_cvterm->cvterm_id(),
                pub_id => $null_pub->pub_id(),
              });
            $product_update_count++;
          }
        }
      }

    } else {
      warn qq|while loading gene name and product file, unknown gene "$gene_uniquename" - skipping\n|;
    }
  }

  warn "loaded $name_update_count names and $product_update_count products " .
    "and added $new_synonym_count synonyms\n";
}

1;
