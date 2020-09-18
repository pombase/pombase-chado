package PomBase::Import::GenericProperty;

=head1 NAME

PomBase::Import::GenericProperty - Load featureprops from a delimited file
   containing the feature uniquename and the new property

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::GenericProperty

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

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::FeatureFinder';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has organism => (is => 'rw', init_arg => undef);
has property_cvterm => (is => 'rw', init_arg => undef);
has feature_uniquename_column => (is => 'rw', init_arg => undef);
has property_column => (is => 'rw', init_arg => undef);

method BUILD {
  my $organism_taxonid = undef;
  my $property_name = undef;
  my $feature_uniquename_column = undef;
  my $property_column = undef;

  my @opt_config = ("organism-taxonid=s" => \$organism_taxonid,
                    "property-name=s" => \$property_name,
                    "feature-uniquename-column=s" => \$feature_uniquename_column,
                    "property-column=s" => \$property_column,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $organism_taxonid || length $organism_taxonid == 0) {
    die "no --organism-taxonid passed to the GenericProperty loader\n";
  }

  my $organism = $self->find_organism_by_taxonid($organism_taxonid);

  if (!defined $organism) {
    die "can't find organism with taxon ID: $organism_taxonid\n";
  }

  $self->organism($organism);

  if (!defined $property_name || length $property_name == 0) {
    die "no --property-name passed to the GenericProperty loader\n";
  }

  my $property_cvterm = $self->get_cvterm('PomBase feature property types',
                                          $property_name);

  if (!defined $property_cvterm) {
    die "can't find cvterm for $property_name\n";
  }

  $self->property_cvterm($property_cvterm);

  if ($feature_uniquename_column) {
    $self->feature_uniquename_column($feature_uniquename_column - 1);
  } else {
    die "no --feature-uniquename-column passed to the GenericProperty loader\n";
  }

  if ($property_column) {
    $self->property_column($property_column - 1);
  } else {
    die "no --property-column passed to the GenericProperty loader\n";
  }
}

method load($fh) {
  my $chado = $self->chado();
  my $config = $self->config();

  my $tsv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  while (my $columns_ref = $tsv->getline($fh)) {
    my $col_count = scalar(@$columns_ref);

    if ($self->feature_uniquename_column() >= $col_count) {
      die "value for --feature-uniquename-column too big at line $.\n"
    }

    if ($self->property_column() >= $col_count) {
      die "value for --property-column too big at line $.\n"
    }

    my $feature = undef;

    my $feature_uniquename = $columns_ref->[$self->feature_uniquename_column()];
    my $property_value = $columns_ref->[$self->property_column()];

    try {
      $feature = $self->find_chado_feature($feature_uniquename);
    } catch {
      warn "line $.: $_";
    };

    if (!defined $feature) {
      next;
    }

    $self->store_featureprop($feature, $self->property_cvterm()->name(), $property_value);
  }
}

1;
