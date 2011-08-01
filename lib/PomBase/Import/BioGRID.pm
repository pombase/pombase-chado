package PomBase::Import::BioGRID;

=head1 NAME

PomBase::Import::BioGRID - Read BioGRID data from a BioGRID tab 2 format into
                           Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::BioGRID

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

use Text::CSV;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::Embl::FeatureRelationshippropStorer';
with 'PomBase::Role::Embl::FeatureRelationshipPubStorer';

has verbose => (is => 'ro');

method load($fh)
{
  my $chado = $self->chado();

  my $csv = Text::CSV->new({ sep_char => "\t" });

  my $genetic_interaction_type =
    $self->get_cvterm('PomBase interaction types', 'interacts_genetically');
  my $physical_interaction_type =
    $self->get_cvterm('PomBase interaction types', 'interacts_physically');

  $csv->column_names ($csv->getline($fh));

  while (my $columns_ref = $csv->getline_hr($fh)) {
    my $biogrid_id = $columns_ref->{"#BioGRID Interaction ID"};;

    my $uniquename_a = $columns_ref->{"Systematic Name Interactor A"};
    my $uniquename_b = $columns_ref->{"Systematic Name Interactor B"};

    my $experimental_system = $columns_ref->{"Experimental System"};
    my $experimental_system_type = $columns_ref->{"Experimental System Type"};

    my $pubmed_id = $columns_ref->{"Pubmed ID"};

    my $organism_interactor = "Organism Interactor";

    my $taxon_a = $columns_ref->{"$organism_interactor A"};
    my $taxon_b = $columns_ref->{"$organism_interactor B"};

    my $phenotype = $columns_ref->{"Phenotypes"};
    my $qualifications = $columns_ref->{"Qualifications"};
    my $tags = $columns_ref->{"Tags"};

    my $source_db = $columns_ref->{"Source Database"};

    if ($taxon_a ne $self->config()->{taxonid} &&
        $taxon_b ne $self->config()->{taxonid}) {
      warn "ignoring interaction of $uniquename_a with $uniquename_b " .
        "because neither gene is a pombe gene\n";
      next;
    }

    my $organism_a = $self->find_organism_by_taxonid($taxon_a);
    my $organism_b = $self->find_organism_by_taxonid($taxon_b);

    if (!defined $organism_a) {
      warn "ignoring $experimental_system_type interaction of $uniquename_a " .
        "with $uniquename_b because taxon $taxon_a isn't in the database\n";
      next;
    }

    if (!defined $organism_b) {
      warn "ignoring $experimental_system_type interaction of $uniquename_a " .
        "with $uniquename_b because taxon $taxon_b isn't in the database\n";
      next;
    }

    if ($uniquename_a eq '-') {
      warn "no systematic name for interactor A in BioGRID ID: $biogrid_id\n";
      next;
    }

    if ($uniquename_b eq '-') {
      warn "no systematic name for interactor B in BioGRID ID: $biogrid_id\n";
      next;
    }

    my $feature_a;
    try {
      $feature_a = $self->find_chado_feature($uniquename_a, 1, 0, $organism_a);
    } catch {
      warn "skipping BioGRID ID $biogrid_id: $_";
    };
    next unless defined $feature_a;

    my $feature_b;
    try {
      $feature_b = $self->find_chado_feature($uniquename_b, 1, 0, $organism_b);
    } catch {
      warn "skipping BioGRID ID $biogrid_id: $_";
    };
    next unless defined $feature_b;

    my $pub = $self->find_or_create_pub($pubmed_id);

    my $rel_type;

    if ($experimental_system_type eq 'genetic') {
      $rel_type = $genetic_interaction_type;
    } else {
      if ($experimental_system_type eq 'physical') {
        $rel_type = $physical_interaction_type;
      } else {
        die "unknown experimental_system_type: $experimental_system_type\n";
      }
    }

    my $rel = $self->store_feature_rel($feature_a, $feature_b, $rel_type);

    $self->store_feature_relationshipprop($rel, 'evidence',
                                          $experimental_system);
    $self->store_feature_relationshipprop($rel, 'source_database',
                                          $source_db);
    $self->store_feature_rel_pub($rel, $pub);
  }
}

1;
