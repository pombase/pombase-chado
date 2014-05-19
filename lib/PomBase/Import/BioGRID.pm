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

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::Embl::FeatureRelationshippropStorer';
with 'PomBase::Role::Embl::FeatureRelationshipPubStorer';
with 'PomBase::Role::InteractionStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');

has organism_taxonid_filter => (is => 'rw', init_arg => undef);
has evidence_code_filter => (is => 'rw', init_arg => undef, isa => 'ArrayRef');
has interaction_note_filter => (is => 'rw', init_arg => undef);

method BUILD
{
  my $organism_taxonid_filter = undef;
  my $evidence_code_filter = undef;
  my $interaction_note_filter = undef;

  my @opt_config = ('organism-taxonid-filter=s' => \$organism_taxonid_filter,
                    'evidence-code-filter=s' => \$evidence_code_filter,
                    'interaction-note-filter=s' => \$interaction_note_filter);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  $self->organism_taxonid_filter($organism_taxonid_filter);

  if (defined $evidence_code_filter) {
    $self->evidence_code_filter([split(/,/, $evidence_code_filter)]);
  }
  if (defined $interaction_note_filter) {
    my %note_hash = ();
    map { $note_hash{$_} = 1; } split(/\|/, $interaction_note_filter);
    $self->interaction_note_filter(\%note_hash);
  }
}

method load($fh)
{
  my $chado = $self->chado();

  my $csv = Text::CSV->new({ sep_char => "\t" });

  $csv->column_names ($csv->getline($fh));

  my $organism_taxonid_filter = $self->organism_taxonid_filter();
  my @evidence_code_filter = @{$self->evidence_code_filter() // []};
  my $interaction_note_filter = $self->interaction_note_filter();

  ROW:
  while (my $columns_ref = $csv->getline_hr($fh)) {
    my $biogrid_id = $columns_ref->{"#BioGRID Interaction ID"};;

    my $uniquename_a = $columns_ref->{"Systematic Name Interactor A"};
    my $uniquename_b = $columns_ref->{"Systematic Name Interactor B"};

    my $experimental_system = $columns_ref->{"Experimental System"};
    my $experimental_system_type = $columns_ref->{"Experimental System Type"};

    my $pubmed_id = 'PMID:' . $columns_ref->{"Pubmed ID"};

    my $organism_interactor = "Organism Interactor";

    my $taxon_a = $columns_ref->{"$organism_interactor A"};
    my $taxon_b = $columns_ref->{"$organism_interactor B"};

    my $phenotype = $columns_ref->{"Phenotypes"};
    my $qualifications = $columns_ref->{"Qualifications"};

    my @qualifications = ();

    if ($qualifications ne '-') {
      @qualifications = split(/\|/, $qualifications);

      if (defined $interaction_note_filter) {
        for my $qualification (@qualifications) {
          if ($interaction_note_filter->{$qualification}) {
            warn "ignoring interaction of $uniquename_a " .
              "<-> $uniquename_b because of interaction note/qualification " .
              qq("$qualification"\n);
            next ROW;
          }
        }
      }
    }

    my $tags = $columns_ref->{"Tags"};

    my $source_db = $columns_ref->{"Source Database"};

    if (@evidence_code_filter) {
      if (grep { $_ eq $experimental_system } @evidence_code_filter) {
        warn "ignoring interaction of $uniquename_a " .
          "<-> $uniquename_b because of evidence/experimental system " .
          qq("$experimental_system"\n);
        next;
      }
    }

    if (defined $organism_taxonid_filter &&
        ($taxon_a ne $organism_taxonid_filter ||
         $taxon_b ne $organism_taxonid_filter)) {
      warn "ignoring interaction of $uniquename_a(taxon $taxon_a) " .
        "with $uniquename_b(taxon $taxon_b) " .
        "because one of the interactors is not from taxon $organism_taxonid_filter\n";
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

    my $rel_type_name;

    if ($experimental_system_type eq 'genetic') {
      $rel_type_name = 'interacts_genetically';
    } else {
      if ($experimental_system_type eq 'physical') {
        $rel_type_name = 'interacts_physically';
      } else {
        die "unknown experimental_system_type: $experimental_system_type\n";
      }
    }

    $self->store_interaction(
      feature_a => $feature_a,
      feature_b => $feature_b,
      rel_type_name => $rel_type_name,
      evidence_type => $experimental_system,
      source_db => $source_db,
      pub => $pub,
      notes => \@qualifications,
    );
  }

  return undef;
}

method results_summary($results)
{
  return '';
}

1;
