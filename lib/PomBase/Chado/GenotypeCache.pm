package PomBase::Chado::GenotypeCache;

=head1 NAME

PomBase::Chado::GenotypeCache - Cache of genotype features used to reduce
                                database accesses

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::GenotypeCache

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

my $populate_sql = qq|
SELECT genotype.feature_id AS genotype_feature_id,
       genotype.name AS genotype_name,

  (SELECT value
   FROM featureprop p
   WHERE p.feature_id = genotype.feature_id
     AND p.type_id IN
       (SELECT cvterm_id
        FROM cvterm
        WHERE name = 'genotype_background')) AS background,

  (SELECT value
   FROM feature_relationshipprop p
   WHERE p.feature_relationship_id = rel.feature_relationship_id
     AND p.type_id IN
       (SELECT cvterm_id
        FROM cvterm
        WHERE name = 'expression') LIMIT 1) AS expression,
  allele.feature_id AS allele_feature_id
FROM feature genotype
JOIN feature_relationship rel ON rel.object_id = genotype.feature_id
JOIN feature allele ON allele.feature_id = rel.subject_id
WHERE allele.type_id IN
    (SELECT cvterm_id
     FROM cvterm
     WHERE name = 'allele')
  AND genotype.type_id IN
    (SELECT cvterm_id
     FROM cvterm
     WHERE name = 'genotype')
ORDER BY genotype.uniquename
|;

with 'PomBase::Role::ChadoUser';

has cache => (is => 'ro', init_arg => undef, lazy_build => 1,
              builder => '_build_cache');

sub make_key {
  my $genotype_name = shift;
  my $genotype_background = shift;
  my $expression_and_allele_ids = shift;

  return ($genotype_name ? $genotype_name : '[NO-NAME]') . '--' .
    ($genotype_background ? $genotype_background : '[NO-BACKGROUND]') . '-- ((' .
    (join " + ", map {
      ($_->{expression} ? $_->{expression} : "[NULL]") . '-=' .
        $_->{allele_feature_id};
    } @$expression_and_allele_ids) . '))';
}

func make_key_from_allele_objects($genotype_name, $genotype_background,
                                  $alleles_and_expression) {
  return make_key($genotype_name, $genotype_background,
                  [map {
                    { expression => $_->{expression},
                        allele_feature_id => $_->{allele}->feature_id(),
                      };
                  } @{$alleles_and_expression}]);
}

method _build_cache {
  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $sth = $dbh->prepare($populate_sql);
  $sth->execute();

  my %collect_hash = ();

  while (my ($genotype_feature_id, $genotype_name, $genotype_background,
             $expression, $allele_feature_id) = $sth->fetchrow_array()) {
    $collect_hash{$genotype_feature_id}->{name} = $genotype_name;
    $collect_hash{$genotype_feature_id}->{background} = $genotype_background;
    push @{$collect_hash{$genotype_feature_id}->{expression_and_allele_ids}}, {
      expression => $expression,
      allele_feature_id => $allele_feature_id,
    };
  }

  my %cache = ();

  my $genotype_rs = $chado->resultset('Sequence::Feature')
    ->search({ 'type.name' => 'genotype' },
             { join => 'type' });

  while (defined (my $genotype = $genotype_rs->next())) {
    my $details = $collect_hash{$genotype->feature_id()};
    my $key = make_key($details->{name}, $details->{background},
                       $details->{expression_and_allele_ids});

    $cache{$key} = $genotype;
  }

  return \%cache;
}

sub get {
  my $self = shift;
  my $genotype_name = shift;
  my $genotype_background = shift;
  my $alleles_and_expression = shift;

  my $key = make_key_from_allele_objects($genotype_name, $genotype_background,
                                        $alleles_and_expression);

  return $self->cache()->{$key}
}

sub put {
  my $self = shift;
  my $genotype_name = shift;
  my $genotype_background = shift;
  my $alleles_and_expression = shift;
  my $genotype = shift;

  my $key = make_key_from_allele_objects($genotype_name, $genotype_background,
                                         $alleles_and_expression);
  $self->cache()->{$key} = $genotype;
}

1;
