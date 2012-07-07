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

use perl5i::2;
use Moose;

use Text::CSV;
use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::Embl::FeatureRelationshipPubStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);
has swap_direction => (is => 'rw', init_arg => undef);
has publication => (is => 'rw', init_arg => undef);
has organism_1 => (is => 'rw', init_arg => undef);
has organism_2 => (is => 'rw', init_arg => undef);

method BUILD
{
  my $swap_direction = 0;
  my $publication_uniquename = undef;
  my $organism_1_taxonid = undef;
  my $organism_2_taxonid = undef;

  my @opt_config = ("swap-direction" => \$swap_direction,
                    "publication=s" => \$publication_uniquename,
                    "organism_1_taxonid=s" => \$organism_1_taxonid,
                    "organism_2_taxonid=s" => \$organism_2_taxonid,
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
  my $organism_2 = $self->find_organism_by_taxonid($organism_2_taxonid);
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
method load($fh)
{
  my $chado = $self->chado();
  my $config = $self->config();

  my $orthologous_to_term =
    $self->get_cvterm('feature_cvtermprop_type', 'assigned_by');

  my $csv = Text::CSV->new({ sep_char => "\t" });

  $csv->column_names(qw(org1_identifier org2_identifiers));

  while (my $columns_ref = $csv->getline_hr($fh)) {
    my $org1_identifier = $columns_ref->{"org1_identifier"};
    my $org2_identifiers = $columns_ref->{"org2_identifiers"};
    my @org2_identifiers = split (',', $org2_identifiers);

    my $org1_feature =
      $self->find_chado_feature($org1_identifier, 0, 0, $self->organism_1());
    if (!defined $org1_feature) {
      die "can't find feature into Chado for $org1_identifier";
    }

    for my $org2_identifier (@org2_identifiers) {
      my $org2_feature =
        $self->find_chado_feature($org1_identifier, 0, 0, $self->organism_2());
      if (!defined $org2_feature) {
        die "can't find feature into Chado for $org2_identifier";
      }

      my $proc = sub {

        my $feature_rel;
        if ($self->swap_direction()) {
          $feature_rel = $self->store_feature_rel($org2_feature, $org1_feature, $orthologous_to_term);
        } else {
          $feature_rel = $self->store_feature_rel($org1_feature, $org2_feature, $orthologous_to_term);
        }

        $self->store_feature_rel_pub($feature_rel, $self->publication());
      };

      try {
        $chado->txn_do($proc);
      } catch {
        warn "Failed to load row: $_\n";
      }
    }
  }
}

method results_summary($results)
{
  return '';
}
1;
