package PomBase::Import::Features;

=head1 NAME

PomBase::Import::Features - load feature without coords or sequence

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::Features

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

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has organism => (is => 'rw', init_arg => undef);
has feature_type => (is => 'rw', init_arg => undef);
has uniquename_column => (is => 'rw', init_arg => undef);
has name_column => (is => 'rw', init_arg => undef);
has reference_column => (is => 'rw', init_arg => undef);
has product_column => (is => 'rw', init_arg => undef);
has date_column => (is => 'rw', init_arg => undef);
has parent_feature_id_column => (is => 'rw', init_arg => undef);
has parent_feature_rel_column => (is => 'rw', init_arg => undef);
has ignore_lines_matching => (is => 'rw', init_arg => undef);
has ignore_short_lines => (is => 'rw', init_arg => undef);
has column_filters => (is => 'rw', init_arg => undef);
has null_pub => (is => 'rw', init_arg => undef);

sub BUILD
{
  my $self = shift;

  my $organism_taxonid = undef;
  my $uniquename_column = undef;
  my $name_column = undef;
  my $reference_column = undef;
  my $product_column = undef;
  my $date_column = undef;
  my $parent_feature_id_column = undef;
  my $parent_feature_rel_column = undef;
  my $feature_type = undef;
  my $ignore_lines_matching = '';
  my $ignore_short_lines = 0;
  my @column_filters = ();

  my @opt_config = ("organism-taxonid=s" => \$organism_taxonid,
                    "feature-type=s" => \$feature_type,
                    "column-filter=s" => \@column_filters,
                    "uniquename-column=s" => \$uniquename_column,
                    "name-column=s" => \$name_column,
                    "reference-column=s" => \$reference_column,
                    "product-column=s" => \$product_column,
                    "date-column=s" => \$date_column,
                    "parent-feature-id-column=s" => \$parent_feature_id_column,
                    "parent-feature-rel-column=s" => \$parent_feature_rel_column,
                    "ignore-lines-matching=s" => \$ignore_lines_matching,
                    "ignore-short-lines" => \$ignore_short_lines,
                  );

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

  if (!defined $uniquename_column) {
    die "no --uniquename-column passed to the Features loader\n";
  }

  $self->uniquename_column($uniquename_column - 1);

  if (!defined $name_column) {
    die "no --name-column passed to the Features loader\n";
  }

  $self->name_column($name_column - 1);

  if (!defined $feature_type) {
    die "no --feature-type passed to the Features loader\n";
  }

  $self->feature_type($feature_type);

  $self->ignore_lines_matching($ignore_lines_matching);
  $self->ignore_short_lines($ignore_short_lines);
  $self->column_filters(\@column_filters);

  if ($reference_column) {
    $self->reference_column($reference_column - 1);
  }
  if ($product_column) {
    $self->product_column($product_column - 1);
  }
  if ($date_column) {
    $self->date_column($date_column - 1);
  }

  if ($parent_feature_id_column && !$parent_feature_rel_column) {
    die "--parent-feature-rel-column is required if " .
      "--parent-feature-id-column is supplied\n";
  }
  if ($parent_feature_rel_column && !$parent_feature_id_column) {
    die "--parent-feature-id-column is required if " .
      "--parent-feature-rel-column is supplied\n";
  }

  if ($parent_feature_id_column) {
    $self->parent_feature_id_column($parent_feature_id_column - 1);
  }
  if ($parent_feature_rel_column) {
    $self->parent_feature_rel_column($parent_feature_rel_column - 1);
  }

  my $null_pub = $self->find_or_create_pub('null');

  $self->null_pub($null_pub);
}

method load($fh) {
  my $uniquename_column = $self->uniquename_column();
  my $name_column = $self->name_column();
  my $feature_type_name = $self->feature_type();
  my $organism = $self->organism();
  my $ignore_short_lines = $self->ignore_short_lines();
  my $ignore_lines_matching_string = $self->ignore_lines_matching();
  my $product_column = $self->product_column();
  my $date_column = $self->date_column();
  my $reference_column = $self->reference_column();
  my $parent_feature_id_column = $self->parent_feature_id_column();
  my $parent_feature_rel_column = $self->parent_feature_rel_column();

  my %filter_conf = ();

  for my $filter_config (@{$self->column_filters()}) {
    if ($filter_config =~ /^(\d)=(.*)/) {
      $filter_conf{$1 - 1} = [split /,/, $2];
    } else {
      die qq|unknown format for --filter-config: "$filter_config"|;
    }
  }

  my $feature_count = 0;

 LINE:
  while (<$fh>) {
    next if /^#|^!/;

    next if $ignore_lines_matching_string && /$ignore_lines_matching_string/;

    chomp $_;

    my @columns = split /\t/, $_;

    if (!$ignore_short_lines && $uniquename_column >= @columns) {
      die "not enough columns for --uniquename-column at: $_\n";
    }
    if (!$ignore_short_lines && $name_column >= @columns) {
      die "not enough columns for --name-column at: $_\n";
    }

    for my $filter_column (keys %filter_conf) {
      my @filter_values = @{$filter_conf{$filter_column}};

      my $found_match = 0;

      for my $filter_value (@filter_values) {
        if ($columns[$filter_column] eq $filter_value) {
          $found_match = 1;
        }
      }

      next LINE unless $found_match;
    }

    my $uniquename = $columns[$uniquename_column];
    my $name = $columns[$name_column] || undef;

    my $feat = $self->store_feature($uniquename, $name, [], $feature_type_name, $organism);

    if (!defined $feat) {
      die "failed to store feature: $uniquename, type $feature_type_name";
    }

    if ($date_column) {
      my $date = $columns[$date_column];
      if ($date) {
        $self->store_featureprop($feat, 'annotation_date', $date)
      }
    }

    if ($product_column) {
      my $product = $columns[$product_column];
      if ($product) {
        my $product_cvterm =
          $self->find_or_create_cvterm('PomBase gene products', $product);

        $self->create_feature_cvterm($feat, $product_cvterm, $self->null_pub(), 0);
      }
    }

    $feature_count++;

    if ($reference_column) {
      my $reference_uniquename = $columns[$reference_column];
      my $pub = $self->find_or_create_pub($reference_uniquename);
      $self->create_feature_pub($feat, $pub);
    }

    if ($parent_feature_id_column && $parent_feature_rel_column) {
      my $parent_feature_rel_name = $columns[$parent_feature_rel_column];
      my $parent_feature_id = $columns[$parent_feature_id_column];
      my $rel_cvterm = $self->get_cvterm('SO_feature_relations', $parent_feature_rel_name);

      my $parent_feature =
        $self->find_chado_feature($parent_feature_id, 0, 0, $organism);

      $self->store_feature_rel($feat, $parent_feature, $parent_feature_rel_name);
    }
  }

  print "loaded $feature_count features of type $feature_type_name\n";
}

1;
