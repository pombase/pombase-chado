package PomBase::Import::Orthologs;

=head1 NAME

PomBase::Import::Orthologs - Load orthologs in tab delimited format

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Orthologs

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Text::Trim qw(trim);

use Try::Tiny;

use Moose;

use Text::CSV;
use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::Embl::FeatureRelationshipPubStorer';
with 'PomBase::Role::Embl::FeatureRelationshippropStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);
has swap_direction => (is => 'rw', init_arg => undef);
has publication => (is => 'rw', init_arg => undef);
has organism_1 => (is => 'rw', init_arg => undef);
has organism_2 => (is => 'rw', init_arg => undef);
has organism_1_term => (is => 'rw', init_arg => undef);

sub BUILD
{
  my $self = shift;

  my $swap_direction = 0;
  my $publication_uniquename = undef;
  my $organism_1_taxonid = undef;
  my $organism_2_taxonid = undef;
  my $org_1_term_name = undef;
  my $org_1_term_cv_name = undef;

  my @opt_config = ("swap-direction" => \$swap_direction,
                    "publication=s" => \$publication_uniquename,
                    "organism_1_taxonid=s" => \$organism_1_taxonid,
                    "organism_2_taxonid=s" => \$organism_2_taxonid,
                    "add_org_1_term_name=s" => \$org_1_term_name,
                    "add_org_1_term_cv=s" => \$org_1_term_cv_name,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  $self->swap_direction($swap_direction);

  if (!defined $publication_uniquename) {
    die "the --publication argument is required\n";
  }

  my $publication = $self->find_or_create_pub($publication_uniquename);
  $self->publication($publication);

  if (!defined $organism_1_taxonid) {
    die "the --organism_1_taxonid argument is required\n";
  }
  if (!defined $organism_2_taxonid) {
    die "the --organism_2_taxonid argument is required\n";
  }
  my $organism_1 = $self->find_organism_by_taxonid($organism_1_taxonid);
  $self->organism_1($organism_1);
  my $organism_2 = $self->find_organism_by_taxonid($organism_2_taxonid);
  $self->organism_2($organism_2);

  if (defined $org_1_term_name && !defined $org_1_term_cv_name) {
    die "--add_org_1_term_name needs --add_org_1_term_cv\n";
  }
  if (!defined $org_1_term_name && defined $org_1_term_cv_name) {
    die "--add_org_1_term_cv needs --add_org_1_term_name\n";
  }

  if (defined $org_1_term_name) {
    $self->organism_1_term($self->get_cvterm($org_1_term_cv_name, $org_1_term_name));

    if (!defined $self->organism_1_term()) {
      die qq(term "$org_1_term_name" not found in cv "$org_1_term_cv_name"\n);
    }
  }
}

=head2 load

 Usage   : $ortholog_import->load($fh);
 Function: Load orthologs in tab-delimited format from a file handle.
           The input must have two columns.  Column 1 has the gene
           identifiers of the first organism.  Columns 2 has a comma
           separated list of the identifiers of ortholous genes in
           organism 2.
 Args    : $fh - a file handle
 Returns : nothing

=cut
sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $orthologous_to_term =
    $self->get_cvterm('sequence', 'orthologous_to');

  my $csv = Text::CSV->new({ sep_char => "\t" });

  $csv->column_names(qw(org1_identifier org2_identifiers));

  my $organism_1_term = $self->organism_1_term();

  my $load_orthologs_count = 0;

  my %seen_orthologs = ();

  my $null_pub = $chado->resultset('Pub::Pub')->find({ uniquename => 'null' });

  ROW: while (my $columns_ref = $csv->getline_hr($fh)) {
    my $org1_identifier = trim($columns_ref->{"org1_identifier"});
    my $org2_identifiers = $columns_ref->{"org2_identifiers"};

    if (!defined $org2_identifiers) {
      warn "not enough columns at line $. of line $org1_identifier - missing TAB character?\n";
      next;
    }

    my %org2_identifiers = ();

    map {
      my $trimmed_identifier = trim($_);
      if (exists $org2_identifiers{$trimmed_identifier}) {
        warn "line $.: Skipping ortholog mentioned twice in input file: " .
          "$org1_identifier <-> $trimmed_identifier\n";
      } else {
        $org2_identifiers{$trimmed_identifier} = 1;
      }
    } split (',', $org2_identifiers);

    my @org2_identifiers = sort keys %org2_identifiers;

    my $org1_feature;
    eval {
      $org1_feature = $self->find_chado_feature($org1_identifier, 1, 0, $self->organism_1());
    };
    if (!defined $org1_feature) {
      warn "can't find feature in Chado for $org1_identifier\n";
      next ROW;
    }

    if (defined $organism_1_term) {
      my $add_term_rs = $org1_feature->search_related('feature_cvterms')
                           ->search({ cvterm_id => $organism_1_term->cvterm_id() });
      if ($add_term_rs->count() == 0) {
        my $feature_cvterm =
          $self->create_feature_cvterm($org1_feature, $organism_1_term, $null_pub, 0);

        $self->add_feature_cvtermprop($feature_cvterm, 'annotation_throughput_type',
                                      'non-experimental');

      }
    }
    for my $org2_identifier (@org2_identifiers) {
      my $seen_key = $org1_identifier . '---' . $org2_identifier;
      if (exists $seen_orthologs{$seen_key}) {
        next;
      } else {
        $seen_orthologs{$seen_key} = 1;
      }

     my $org2_feature;
      eval {
        $org2_feature = $self->find_chado_feature($org2_identifier, 1, 0, $self->organism_2());
      };
      if (!defined $org2_feature) {
        warn "can't find feature in Chado for $org2_identifier\n";
        next ROW;
      }

      my $proc = sub {
        my $feature_rel;
        if ($self->swap_direction()) {
          $feature_rel = $self->store_feature_rel($org2_feature, $org1_feature, $orthologous_to_term, 1);
        } else {
          $feature_rel = $self->store_feature_rel($org1_feature, $org2_feature, $orthologous_to_term, 1);
        }

        $self->store_feature_relationshipprop($feature_rel,
                                              annotation_throughput_type => 'non-experimental');

        $load_orthologs_count++;

        $self->store_feature_rel_pub($feature_rel, $self->publication());
      };

      try {
        $chado->txn_do($proc);
      } catch {
        if (/duplicate key value violates unique constraint/) {
          warn "line $.: Skipping ortholog that's already loaded: $org1_identifier <-> $org2_identifier\n";
        } else {
          warn "line $.: Failed to load ortholog $org1_identifier <-> $org2_identifier:\n$_\n";
        }
      };
    }
  }

  return $load_orthologs_count;
}

sub results_summary {
  my $self = shift;
  my $results = shift;

  return '';
}
1;
