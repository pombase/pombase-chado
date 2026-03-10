package PomBase::Import::LegacyControlledCuration;

=head1 NAME

PomBase::Import::LegacyControlledCuration - read a TSV file of curation that
    was formally in the contig files as /controlled_curation qualifiers.
    See: https://github.com/pombase/pombase-chado/issues/1330

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::LegacyControlledCuration

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

use Text::Trim qw(trim);

use Try::Tiny;

use Moose;

use Text::CSV;
use Getopt::Long qw(GetOptionsFromArray);

use PomBase::Chado::ExtensionProcessor;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has organism => (is => 'rw', init_arg => undef);

has extension_processor => (is => 'ro', init_arg => undef, lazy_build => 1);

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
  my $organism_taxonid = undef;

  my @opt_config = ("organism-taxonid=s" => \$organism_taxonid);

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $organism_taxonid || length $organism_taxonid == 0) {
    die "no --organism-taxonid passed to the Features loader\n";
  }

  my $organism = $self->find_organism_by_taxonid($organism_taxonid);

  if (!defined $organism) {
    die "can't find organism with taxon ID: $organism_taxonid\n";
  }

  $self->organism($organism);
}

sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $csv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  $csv->column_names($csv->getline($fh));

  my @column_names = $csv->column_names();

  my $null_pub = $self->find_or_create_pub('null');

 LINE:
  while (defined (my $line = $fh->getline())) {
    if (!$csv->parse($line)) {
      die "Parse error at line $.: ", $csv->error_input(), "\n";
    }

    my %columns = ();

    my @fields = $csv->fields();

    if (@fields < 10) {
      warn "not enough columns, got ", scalar(@fields),
        " - ignoring line $.\n";
      next;
    }

    @columns{ $csv->column_names() } = @fields;

    my $file_name = trim($columns{"file_name"});
    my $systematic_id = trim($columns{"systematic_id"});
    my $feature_type = trim($columns{"feature_type"});
    my $cv_name = trim($columns{"cv_name"});
    my $date = trim($columns{"date"});
    my $db_xref = trim($columns{"db_xref"});
    my $evidence_code = trim($columns{"evidence"});
    my $qualifier = trim($columns{"qualifier"});
    my $residue = trim($columns{"residue"});
    my $term_name = trim($columns{"term"}) =~ s/  +/ /gr;
    my $with = trim($columns{"with"});
    my $annotation_extension = trim($columns{"annotation_extension"});

    if ($cv_name eq 'gene_ex') {
      if ($feature_type eq 'mRNA') {
        $cv_name = 'PomGeneExProt';
      } else {
        $cv_name = 'PomGeneExRNA';
      }

      if ($qualifier) {
        if ($qualifier eq 'present' or $qualifier eq 'absent') {
          $term_name =~ s/\s+level$//;
        }
        $term_name .= " $qualifier";

        $qualifier = undef;
      }
    }

    my $proc = sub {
      my $cvterm = $self->find_or_create_cvterm($cv_name, $term_name);

      my $pub;

      if ($db_xref) {
        $pub = $self->get_pub_from_db_xref($db_xref || '', $db_xref);
      } else {
        $pub = $null_pub;
      }

      my $feature;

      try {
        $feature = $self->find_chado_feature("$systematic_id", 0, 0, $self->organism());
      }
      catch {
        warn "can't find feature in Chado for $systematic_id - skipping line $.\n";
      };

      if (!defined $feature) {
        return;
      }

      my $featurecvterm =
        $self->create_feature_cvterm($feature, $cvterm, $pub, 0);

      if ($date) {
        $self->add_feature_cvtermprop($featurecvterm, date => $date);
      }
      if ($qualifier) {
        $self->add_feature_cvtermprop($featurecvterm, qualifier => $qualifier);
      }

      if ($evidence_code) {
        my $long_evidence =
          $self->config()->{evidence_types}->{$evidence_code}->{name};
        if (defined $long_evidence) {
          $self->add_feature_cvtermprop($featurecvterm, 'evidence',
                                        $long_evidence);

        } else {
          die "unknown evidence code: $evidence_code at line $.\n";
        }
      }

      my $err = undef;

      my $processor = $self->extension_processor();

      try {
        $processor->process_one_annotation($featurecvterm, $annotation_extension);
      }
      catch {
        chomp $_;
        $err = $_;
      };

      if ($err) {
        $featurecvterm->delete();
        die "line $.: $err\n";
      }
    };

    try {
      $chado->txn_do($proc);
    }
    catch {
      warn "line ", $fh->input_line_number(), ": ($_)\n";
    }
  }
}

1;
