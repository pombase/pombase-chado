package PomBase::QCQueries::QueryGenotypeComments;

=head1 NAME

PomBase::QCQueries::QueryGenotypeComments -

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::QCQueries::QueryGenotypeComments

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2022 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose;

use open ':encoding(UTF-8)';
binmode(STDERR, 'encoding(UTF-8)');

sub description {
  my $self = shift;

  return "Query genotype comments and session IDs";
}

with 'PomBase::Checker';

sub _allele_props {
  my $allele = shift;

  my %props = ();

  my $props_rs = $allele->featureprops()->search({}, { prefetch => 'type' });

  map {
    $props{$_->type()->name()} = $_->value();
  } $props_rs->all();

  return %props;
}

sub _make_display_name {
  my $genotype = shift;

  my $alleles_rs = $genotype
    ->search_related('feature_relationship_objects')
    ->search({ 'type.name' => 'part_of', 'type_2.name' => 'allele' },
             { join => ['type', { subject => 'type' }]});

  my @allele_display_names = map {
    my $allele = $_->subject();
    my %allele_props = _allele_props($allele);

    my $expression_prop = $_->feature_relationshipprops()
      ->search({ 'type.name' => 'expression' }, { join => 'type' })
               ->first();

    my $expression = 'unknown_expression';
    if (defined $expression_prop) {
      $expression = $expression_prop->value();
    }

    my $allele_display_name =
      ($allele->name() // 'unnamed') . '(' . ($allele_props{description} // 'unrecorded') .
      ")[$expression]";

    $allele_display_name =~ s/ /_/g;
    $allele_display_name =~ s/_product_level//g;

    $allele_display_name;
  } $alleles_rs->all();

  return join " ", @allele_display_names;
}

sub check {
  my $self = shift;

  my $rs = $self->chado()->resultset("Sequence::Feature")
    ->search(
      {
        'type.name' => 'genotype',
        'type_2.name' => 'genotype_background',
        'type_3.name' => 'canto_session',
      },
      {
        join => [
          'type',
          {
            featureprops => 'type',
          },
          {
            featureprops => 'type',
          }
        ],
        '+select' => ['featureprops.value', 'featureprops_2.value', ],
        '+as'     => ['genotype_background', 'canto_session'],
      });

  while (defined (my $genotype = $rs->next())) {
    my $genotype_display_name = _make_display_name($genotype);

    print $genotype->get_column('genotype_background'), "\t",
      $genotype->get_column('canto_session'), "\t",
      $genotype_display_name, "\n";
  }
}


1;
