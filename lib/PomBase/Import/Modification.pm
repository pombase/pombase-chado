package PomBase::Import::Modification;

=head1 NAME

PomBase::Import::Modification - Load PSI-MOD bulk annotation in TSV format

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Modification

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

use Text::CSV;
use Getopt::Long qw(GetOptionsFromArray);

use PomBase::Chado::ExtensionProcessor;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');
has organism_taxonid => (is => 'rw', init_arg => undef);
has organism => (is => 'rw', init_arg => undef);
has extension_processor => (is => 'ro', init_arg => undef, lazy => 1,
                            builder => '_build_extension_processor');

method _build_extension_processor
{
  my $processor = PomBase::Chado::ExtensionProcessor->new(chado => $self->chado(),
                                                          config => $self->config(),
                                                          pre_init_cache => 1,
                                                          verbose => $self->verbose());
  return $processor;
}

method BUILD
{

}

method load($fh)
{
  my $chado = $self->chado();

  my $tsv = Text::CSV->new({ sep_char => "\t" });

  $tsv->column_names($tsv->getline($fh));

  while (my $columns_ref = $tsv->getline($fh)) {
    my ($systematic_id, $gene_name, $psi_mod_term_id, $evidence_code, $residue, $extension, $pubmedid, $taxonid, $date) =
      map { $_->trim() || undef } @$columns_ref;

    if (!defined $systematic_id) {
      die qq(mandatory column value for systematic ID missing at line $.\n);
    }
    if (!defined $psi_mod_term_id) {
      die qq(mandatory column value for PSI-MOD ID missing at line $.\n);
    }
    if (!defined $evidence_code) {
      die qq(mandatory column value for evidence missing at line $.\n);
    }
    if (!defined $pubmedid) {
      die qq(mandatory column value for reference missing at line $.\n);
    }
    if (!defined $taxonid) {
      die qq(mandatory column value for taxon missing at line $.\n);
    }
    if (!defined $date) {
      die qq(mandatory column value for date missing at line $.\n);
    }


    my $mod_cvterm = $self->find_cvterm_by_term_id($psi_mod_term_id);

    if (!defined $mod_cvterm) {
      die qq(can't find term "$psi_mod_term_id" in the database\n);
    }

    my $organism = $self->find_organism_by_taxonid($taxonid);

    my $feature;
    try {
      $feature = $self->find_chado_feature($systematic_id, 1, 0, $organism);
    } catch {
      warn "skipping annotation: $_";
    };
    next unless defined $feature;

    if (defined $gene_name && defined $feature->name() &&
        $feature->name() ne $gene_name) {
      warn qq(gene name "$gene_name" from the input file doesn't match ) .
        qq(the gene name for $systematic_id from Chado ") . $feature->name() .
        qq("\n);
      next;
    }
    my $pub = $self->find_or_create_pub($pubmedid);

    my $feature_cvterm =
      $self->create_feature_cvterm($feature, $mod_cvterm, $pub, 0);

    my $long_evidence =
      $self->config()->{evidence_types}->{$evidence_code}->{name};
    $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                  $long_evidence);

    if (defined $residue) {
      $residue =~ s/^residue=//;
      $self->add_feature_cvtermprop($feature_cvterm, 'residue', $residue);
    }

    $self->add_feature_cvtermprop($feature_cvterm, 'date', $date);

    if (defined $extension) {
      $self->extension_processor()->process_one_annotation($feature_cvterm, $extension);
    }
  }
}
