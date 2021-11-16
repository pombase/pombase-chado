package PomBase::Chado::AddEcoEvidenceCodes;

=head1 NAME

PomBase::Chado::AddEcoEvidenceCodes - using a mapping file, add an ECO
    evidence code as a feature_cvtermprop with prop type "eco_evidence" based
    on the existing "evidence" prop

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::AddEcoEvidenceCodes

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
use Moose;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';

with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::FeatureCvtermCreator';

has options => (is => 'ro', isa => 'ArrayRef');

has eco_map => (is => 'rw', init_arg => undef);


sub BUILD
{
  my $self = shift;
  my $eco_mapping_file = undef;

  my @opt_config = ('eco-mapping-file=s' => \$eco_mapping_file);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $eco_mapping_file) {
    die "no --mapping-file argument\n";
  }


  my %eco_map = ();

  open my $eco_mapping_fh, '<', $eco_mapping_file or
    die "can't open mapping file, $eco_mapping_file: $!\n";

  while (defined (my $line = <$eco_mapping_fh>)) {
    chomp $line;

    my ($pombase_evidence, $eco_id) = split /\t/, $line;

    $pombase_evidence = lc $pombase_evidence;

    $pombase_evidence =~ s/^\s+//;
    $pombase_evidence =~ s/\s+$//;

    $pombase_evidence =~ s/\s+evidence$//;

    $eco_map{$pombase_evidence} = $eco_id;
    $eco_map{"$pombase_evidence evidence"} = $eco_id;
  }

  $self->eco_map(\%eco_map);

}

sub process
{
  my $self = shift;

  my %eco_map = %{$self->eco_map()};

  my $where =
    "me.feature_cvterm_id IN
      (SELECT feature_cvterm_id FROM pombase_feature_cvterm_ext_resolved_terms fc
        WHERE fc.base_cv_name = 'fission_yeast_phenotype')";


  my $rs = $self->chado()->resultset('Sequence::FeatureCvtermprop')
    ->search({ 'type.name' => 'evidence' },
             {
               where => \$where,
               join => 'type'
             });

  my %missing_evidence_codes = ();

  while (defined (my $prop = $rs->next())) {
    my $pombase_ev_code = lc $prop->value();

    if (!exists $eco_map{$pombase_ev_code}) {
      $missing_evidence_codes{$pombase_ev_code} = 1;
    }
  }

  if (keys %missing_evidence_codes > 0) {
    warn "PomBase evidence codes not in ECO mapping file:\n";
    map {
      warn "  $_\n";
    } sort keys %missing_evidence_codes;
  }
}

1;
