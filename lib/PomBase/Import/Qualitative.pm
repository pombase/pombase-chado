package PomBase::Import::Qualitative;

=head1 NAME

PomBase::Import::Qualitative - Read bulk qualitative expression data

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Qualitative

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

use Text::Trim qw(trim);

use Try::Tiny;

use Moose;

use Text::CSV;
use Getopt::Long qw(GetOptionsFromArray);

use PomBase::Chado::ExtensionProcessor;
use PomBase::Chado::GeneExQualifiersUtil;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';

with 'PomBase::Importer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');
has extension_processor => (is => 'ro', init_arg => undef, lazy => 1,
                            builder => '_build_extension_processor');

has gene_ex_qualifiers_array => (is => 'rw', init_arg => undef);

sub _build_gene_ex_qualifiers {
  my $self = shift;
  my @gene_ex_qualifiers = @{$self->gene_ex_qualifiers_array()};

  my %gene_ex_qualifiers = map { ($_, 1) } @gene_ex_qualifiers;

  return \%gene_ex_qualifiers;
}
has gene_ex_qualifiers => (is => 'rw', init_arg => undef, lazy_build => 1);

sub _build_extension_processor {
  my $self = shift;
  my $processor = PomBase::Chado::ExtensionProcessor->new(chado => $self->chado(),
                                                          config => $self->config(),
                                                          pre_init_cache => 1,
                                                          verbose => $self->verbose());
  return $processor;
}

sub BUILD {
  my $self = shift;
  my $gene_ex_qualifiers_file = undef;

  my $gene_ex_qualifier_util = PomBase::Chado::GeneExQualifiersUtil->new();

  my @opt_config = ("gene-ex-qualifiers=s" => \$gene_ex_qualifiers_file);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $gene_ex_qualifiers_file) {
    croak qq(the "qualitative" import type needs a --gene-ex-qualifiers option);
  }

  my $gene_ex_qualifiers = $gene_ex_qualifier_util->read_qualifiers($gene_ex_qualifiers_file);

  croak "failed to read gene_ex_qualifiers from $gene_ex_qualifiers_file"
    unless $gene_ex_qualifiers;

  $self->gene_ex_qualifiers_array($gene_ex_qualifiers);
}

sub load {
  my $self = shift;
  my $fh = shift;

  my $file_name = $self->file_name_of_fh($fh);

  my $chado = $self->chado();

  my $tsv = Text::CSV->new({ sep_char => "\t" });

  while (my $columns_ref = $tsv->getline($fh)) {
    if (@$columns_ref == 1 && length(trim($columns_ref->[0])) == 0) {
      next;
    }
    my ($first_value, $gene_name, $type, $evidence_code, $level, $extension,
        $pubmedid, $taxonid, $date) =
      map { trim($_) || undef } @$columns_ref;

    if ($first_value =~ /^#/ || $first_value =~ /^#?systematic.id/i) {
      $self->parse_submitter_line($first_value);
      # skip comments and header
      next;
    }

    my $systematic_id = $first_value;

    if (!defined $systematic_id) {
      die qq(mandatory column value for systematic ID missing at line $.\n);
    }
    if (!defined $type) {
      die qq(mandatory column value for feature type missing at line $.\n);
    }
    if (!grep { $_ eq lc $type } ("rna", "protein", "ribosomal density")) {
      die qq(the type column must be either "RNA", "protein" or "ribosomal density", not "$type"\n);
    }
    if (!defined $evidence_code) {
      die qq(mandatory column value for evidence missing at line $.\n);
    }
    if (!defined $level) {
      die qq(mandatory column value for expression level missing at line $.\n);
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

    my $proc = sub {

    my $pub = $self->find_or_create_pub($pubmedid);

    $self->record_pub_object($pubmedid, $pub);

    my $type_cvterm_name;
    if ($type eq 'RNA' || $type eq 'protein') {
      $type_cvterm_name = "$type level";
    } else {
      $type_cvterm_name = $type;
    }

    my $cv_name;

    if ($type eq 'RNA') {
      $cv_name = 'PomGeneExRNA';
    } else {
      if ($type eq 'protein') {
        $cv_name = 'PomGeneExProt';
      } else {
        $cv_name = 'PomGeneExRD';
      }
    }

    if (exists $self->gene_ex_qualifiers()->{$level}) {
      $type_cvterm_name .= " $level";
    } else {
      die qq("$level" is not a valid qualifier for gene expression annotation in line:\n@$columns_ref\n);
    }

    my $type_cvterm = $self->find_cvterm_by_name($cv_name, $type_cvterm_name);

    if (!defined $type_cvterm) {
      die qq(can't find gene expression term "$type_cvterm_name" in the database\n);
    }

    my $feature_cvterm =
      $self->create_feature_cvterm($feature, $type_cvterm, $pub, 0);

    $self->add_feature_cvtermprop($feature_cvterm, 'annotation_throughput_type',
                                  'high throughput');

    my $evidence_config = $self->config()->{evidence_types}->{$evidence_code};
    if (!defined $evidence_config) {
      die qq(unknown evidence code "$evidence_code"\n);
    }
    my $long_evidence = $evidence_config->{name};
    $self->add_feature_cvtermprop($feature_cvterm, 'evidence', $long_evidence);

    $self->add_feature_cvtermprop($feature_cvterm, 'date', $date);

    if (defined $extension) {
      $self->extension_processor()->process_one_annotation($feature_cvterm, $extension);
    }

    $self->increment_ref_annotation_count($pubmedid);

    };

    try {
      $chado->txn_do($proc);
    }
    catch {
      warn "Failed to load row: $_\n";
    }
  }

  if (defined $file_name) {
    $self->store_annotation_file_curator($file_name, 'qualitative_gene_expression');
  }

  return undef;
}

1;
