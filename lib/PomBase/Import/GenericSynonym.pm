package PomBase::Import::GenericSynonym;

=head1 NAME

PomBase::Import::GenericSynonym - Load feature synonyms from a delimited file
   containing the feature uniquenames and synonyms


=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::GenericSynonym

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
use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::FeatureFinder';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has publication_uniquename_column => (is => 'rw', init_arg => undef);
has feature_uniquename_column => (is => 'rw', init_arg => undef);
has feature_name_column => (is => 'rw', init_arg => undef);
has synonym_column => (is => 'rw', init_arg => undef);


sub BUILD {
  my $self = shift;
  my $feature_uniquename_column = undef;
  my $feature_name_column = undef;
  my $synonym_column = undef;
  my $publication_uniquename_column = undef;

  my @opt_config = ("feature-uniquename-column=s" => \$feature_uniquename_column,
                    "feature-name-column=s" => \$feature_name_column,
                    "synonym-column=s" => \$synonym_column,
                    "publication-uniquename-column=s" => \$publication_uniquename_column,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if ($feature_uniquename_column && $feature_name_column) {
    die "pass only one of --feature-uniquename-column or --feature-name-column to the GenericSynonym loader\n";
  }

  if ($feature_uniquename_column || $feature_name_column) {
    if ($feature_uniquename_column) {
      $self->feature_uniquename_column($feature_uniquename_column - 1);
    }
    if ($feature_name_column) {
      $self->feature_name_column($feature_name_column - 1);
    }
  } else {
    die "no --feature-uniquename-column or --feature-name-column passed to the GenericSynonym loader\n";
  }

  if ($synonym_column) {
    $self->synonym_column($synonym_column - 1);
  } else {
    die "no --synonym-column passed to the GenericSynonym loader\n";
  }

  if ($publication_uniquename_column) {
    $self->publication_uniquename_column($publication_uniquename_column - 1);
  }
}

sub load {
  my $self = shift;
  my $fh = shift;

  my $chado = $self->chado();
  my $config = $self->config();

  my $tsv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  while (my $columns_ref = $tsv->getline($fh)) {
    my $col_count = scalar(@$columns_ref);

    if ($columns_ref->[0] =~ /^#/) {
      next;
    }

    if ($self->feature_uniquename_column() &&
        $self->feature_uniquename_column() >= $col_count) {
      die "value for --feature-uniquename-column too large at line $.\n"
    }

    if ($self->feature_name_column() && $self->feature_name_column() >= $col_count) {
      die "value for --feature-name-column too large at line $.\n"
    }

    if ($self->synonym_column() >= $col_count) {
      die "value for --synonym-column too large at line $.\n"
    }

    my $feature = undef;

    if (defined $self->feature_uniquename_column()) {
      my $feature_uniquename = $columns_ref->[$self->feature_uniquename_column()];

      try {
        $feature = $self->find_chado_feature($feature_uniquename);
      } catch {
        warn "line $.: searched for uniquename '$feature_uniquename' - $_";
      };

      if (!defined $feature) {
        next;
      }
    }

    if (defined $self->feature_name_column()) {
      my $feature_name = $columns_ref->[$self->feature_name_column()];

      try {
        $feature = $self->find_chado_feature($feature_name, 1);
      } catch {
        warn "line $.: searched for name '$feature_name' - $_";
      };

      if (!defined $feature) {
        next;
      }
    }

    my $synonym_value = $columns_ref->[$self->synonym_column()];

    if ($synonym_value =~ /^\s*$/) {
      warn "value missing at line $. - skipping\n";
      next;
    }

    my $publication_uniquename = undef;

    my $publication_uniquename_column = $self->publication_uniquename_column();

    if ($publication_uniquename_column) {
      if ($publication_uniquename_column >= $col_count) {
        die "value for --publication-uniquename-column too large at line $.\n"
      }

      $publication_uniquename = $columns_ref->[$publication_uniquename_column];
    }

    $self->store_feature_synonym($feature, $synonym_value, 'exact', 1,
                                 $publication_uniquename);
  }
}

1;
