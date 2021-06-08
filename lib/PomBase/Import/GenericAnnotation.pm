package PomBase::Import::GenericAnnotation;

=head1 NAME

PomBase::Import::GenericAnnotation - read a generic file containing annotations

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::GenericAnnotation

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

  $csv->column_names(qw(systematic_id feature_name term_id evidence_code publication_id date));

  my $null_pub = $self->find_or_create_pub('null');


 LINE:
  while (defined (my $line = $fh->getline())) {
    next if $line =~ /^\s*#/;

    if (!$csv->parse($line)) {
      die "Parse error at line $.: ", $csv->error_input(), "\n";
    }

    my %columns = ();

    my @fields = $csv->fields();

    if (@fields != 6) {
      warn "needed 6 columns, got ", scalar(@fields),
        " - ignoring line $.\n";
      next;
    }

    @columns{ $csv->column_names() } = @fields;

    my $systematic_id = trim($columns{"systematic_id"});
    my $feature_name = trim($columns{"feature_name"})
    my $term_id = trim($columns{"term_id"});
    my $evidence_code = trim($columns{"evidence_code"});
    my $publication_id = trim($columns{"publication_id"});
    my $date = trim($columns{"date"});

    my $long_evidence = undef;
    if ($evidence_code) {
      $long_evidence = $self->config()->{evidence_types}->{$evidence_code}->{name};
      if (!$long_evidence) {
        $long_evidence = $evidence_code;
      }
    }

    my @pubs = ();

    if ($publication_id) {
      @pubs = map {
        my $db_reference = $_;
        $self->find_or_create_pub($db_reference);
      } split /\|/, $publication_id;
    }

    if (!@pubs) {
      push @pubs, $null_pub;
    }

    next unless $systematic_id;

    my $proc = sub {
      my $feature;

      try {
        $feature = $self->find_chado_feature("$systematic_id", 1, 1, $self->organism());
      } catch {
        warn "can't find feature in Chado for $systematic_id - skipping line $.\n";
      };

      if (!defined $feature) {
        return;
      }

      my $cvterm = $self->find_cvterm_by_term_id($term_id);

      if (!defined $cvterm) {
        warn "can't load annotation for $systematic_id, line $. - $term_id not found in database\n";
        return;
      }

      my $feature_cvterm =
        $self->create_feature_cvterm($feature, $cvterm, $pubs[0], 0);

      if (@pubs > 1) {
        warn "ignored ", (@pubs - 1), " extra refs for ", $feature->uniquename(), "\n";
      }

      $self->add_feature_cvtermprop($feature_cvterm, 'annotation_throughput_type',
                                    'non-experimental');

      if ($long_evidence) {
        $self->add_feature_cvtermprop($feature_cvterm, 'evidence', $long_evidence);
      }
      if ($date) {
        $self->add_feature_cvtermprop($feature_cvterm, 'date', $date);
      }
    };

    try {
      $chado->txn_do($proc);
    } catch {
      warn "Failed to load row: $_\n";
    }
  }

  if (!$csv->eof()){
    $csv->error_diag();
  }

}

1;
