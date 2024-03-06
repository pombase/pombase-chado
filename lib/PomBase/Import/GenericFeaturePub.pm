package PomBase::Import::GenericFeaturePub;

=head1 NAME

PomBase::Import::GenericFeaturePub - read a file containing features and PMIDs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::GenericFeaturePub

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2024 Kim Rutherford, all rights reserved.

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
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::FeatureStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has organism => (is => 'rw', init_arg => undef);
has feature_pub_source => (is => 'rw', init_arg => undef);
has feature_uniquename_column => (is => 'rw', init_arg => undef);
has reference_column => (is => 'rw', init_arg => undef);

sub BUILD {
  my $self = shift;
  my $organism_taxonid = undef;
  my $feature_pub_source = undef;
  my $feature_uniquename_column = undef;
  my $reference_column = undef;

  my @opt_config = ("organism-taxonid=s" => \$organism_taxonid,
                    "feature-pub-source=s" => \$feature_pub_source,
                    "feature-uniquename-column=s" => \$feature_uniquename_column,
                    "reference-column=s" => \$reference_column,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $organism_taxonid || length $organism_taxonid == 0) {
    die "no --organism-taxonid passed to the loader\n";
  }

  my $organism = $self->find_organism_by_taxonid($organism_taxonid);

  if (!defined $organism) {
    die "can't find organism with taxon ID: $organism_taxonid\n";
  }

  $self->organism($organism);

  if (!defined $feature_pub_source) {
    die "no --feature-pub-source passed to the loader\n";
  }

  $self->feature_pub_source($feature_pub_source);

  if (defined $feature_uniquename_column) {
    $self->feature_uniquename_column($feature_uniquename_column - 1);
  } else {
    die "no --feature-uniquename-column passed to the loader\n";
  }

  if (defined $reference_column) {
    $self->reference_column($reference_column - 1);
  } else {
    die "no --reference-column passed to the loader\n";
  }
}

sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $reference_column = $self->reference_column();
  my $feature_pub_source = $self->feature_pub_source();

  my %seen_feature_pubs = ();

  my $tsv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  while (my $columns_ref = $tsv->getline($fh)) {
    my $col_count = scalar(@$columns_ref);

    next if $col_count == 0;

    if ($columns_ref->[0] =~ /^#/ || $columns_ref->[0] =~ /uniquename/) {
      next;
    }

    if ($self->feature_uniquename_column() >= $col_count) {
      warn "line $. is too short: the value for --feature-uniquename-column is ",
        $self->feature_uniquename_column(), "\n";
      next;
    }

    if ($self->reference_column() >= $col_count) {
      warn "line $. is too short: the value for --reference-column is ",
        $self->reference_column(), "\n";
      next;
    }

    my $feature = undef;

    my $feature_uniquename = $columns_ref->[$self->feature_uniquename_column()];

    my $reference_value = $columns_ref->[$reference_column];

    my $seen_feature_pubs_key = "$feature_uniquename--$reference_value";
    if ($seen_feature_pubs{$seen_feature_pubs_key}) {
      next;
    } else {
      $seen_feature_pubs{$seen_feature_pubs_key} = 1;
    }

    try {
      $feature = $self->find_chado_feature($feature_uniquename);
    } catch {
      warn "line $.: failed to find feature: $_";
    };

    if (!defined $feature) {
      next;
    }


    my $reference = $self->find_or_create_pub($reference_value);

    my $feature_pub = $self->find_or_create_feature_pub($feature, $reference);
    $self->store_feature_pubprop($feature_pub, 'feature_pub_source',
                                 $feature_pub_source);
  }
}

1;
