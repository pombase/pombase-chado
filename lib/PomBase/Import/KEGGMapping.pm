package PomBase::Import::KEGGMapping;

=head1 NAME

PomBase::Import::KEGGMapping - Load the pombe KEGG mapping

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::KEGGMapping

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
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::CvtermpropStorer';
with 'PomBase::Role::FeatureStorer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');

# the KEGG organism prefix which we will match then remove, eg. the "spo" in
# "spo:SPAC1002.09c  path:spo00010"
has organism_prefix => (is => 'rw', init_arg => undef);

has organism => (is => 'rw', init_arg => undef);


method BUILD {
  my $organism_taxonid = undef;
  my $organism_prefix = undef;

  my @opt_config = ('organism-taxonid=s' => \$organism_taxonid,
                    'organism-prefix=s' => \$organism_prefix);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
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

  if (!defined $organism_prefix) {
    die "the --organism-prefix argument is required\n";
  }

  $self->organism_prefix($organism_prefix);
}

method load($fh) {
  my $chado = $self->chado();

  my $tsv = Text::CSV->new({ sep_char => "\t" });

  while (my $columns_ref = $tsv->getline($fh)) {
    if (@$columns_ref != 2) {
      die qq|input file needs exactly two columns - error reading "|,
        join " ", @$columns_ref;
    }
    my ($gene_id, $pathway_id) = map { $_->trim() || undef } @$columns_ref;

    my $organism_prefix = $self->organism_prefix();
    $gene_id =~ s/^$organism_prefix://;

    my $gene = undef;

    try {
      $gene = $self->find_chado_feature($gene_id, 1, 1, $self->organism());
    } catch {
      warn "$_\n";
    };

    if (!defined $gene) {
      warn "can't find gene in Chado for: $gene_id - skipping\n";
      next;
    }

    $pathway_id =~ s/^path://;

    $self->store_featureprop($gene, 'kegg_pathway', $pathway_id);

  }
}

1;
