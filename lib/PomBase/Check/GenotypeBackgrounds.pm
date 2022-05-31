package PomBase::Check::GenotypeBackgrounds;

=head1 NAME

PomBase::Check::GenotypeBackgrounds - Check the genotype backgrounds and report anything
                               that shouldn't be there

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Check::GenotypeBackgrounds

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose;

use utf8;

use open ':encoding(utf8)';

binmode(STDOUT, ":utf8");

sub description {
  my $self = shift;

  return "Check the genotype backgrounds and report anything that shouldn't be there";
}

with 'PomBase::Checker';

sub clean_string {
  my $str = shift;

  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  $str =~ s/\s+/ /;

  return $str;
}

sub check {
  my $self = shift;

  my %removable_bits = (
    'kanR' => 1,
    'KanR' => 1,
    'hphR' => 1,
    'natR' => 1,
    'KanMX' => 1,
    'KanMX6' => 1,
    'leu1-32' => 1,
    'his3-27' => 1,
    'his6-366' => 1,
    'ura4-D18' => 1,
    'h+' => 1,
    'h-' => 1,
    'h−' => 1,
    'h90' => 1,
    'ade6-M216' => 1,
    'ura4-D19' => 1,
    'ura4-D6' => 1,
    'ura4-294' => 1,
  );

  my $allele_rs = $self->chado()->resultset("Sequence::Feature")
    ->search({ 'type.name' => 'allele' },
             { join => 'type' });

  while (defined (my $allele = $allele_rs->next())) {
    my $allele_name = $allele->name();

    next if !$allele_name;

    $allele_name = clean_string($allele_name);

    $removable_bits{$allele_name} = 1;

    $allele_name =~ s/delta$/Δ/g;

    $removable_bits{$allele_name} = 1;
  }

  my $gene_rs = $self->chado()->resultset("Sequence::Feature")
    ->search({ 'type.name' => 'gene' },
             { join => 'type' });

  while (defined (my $gene = $gene_rs->next())) {
    my $gene_name = $gene->name();

    next if !$gene_name;

    $gene_name = clean_string($gene_name);

    $removable_bits{$gene_name} = 1;
    $removable_bits{"$gene_name-GFP"} = 1;
    $removable_bits{"$gene_name+"} = 1;
    $removable_bits{"$gene_name+"} = 1;
    $removable_bits{$gene_name . "delta"} = 1;
    $removable_bits{$gene_name . "Δ"} = 1;
  }

  my $rs = $self->chado()->resultset("Sequence::Featureprop")
    ->search({ 'type.name' => 'genotype_background',
               'type_2.name' => 'genotype' },
             {
               join => ['type', { feature => 'type' }]
             });

  my @removable_bits = keys %removable_bits;

  map {
    $removable_bits{"$_,"} = 1;
  } @removable_bits;

  my $count = 0;
  my %seen = ();

  while (defined (my $background_prop = $rs->next())) {
    my $orig_background = clean_string($background_prop->value());

    my $background = $orig_background;

    $background =~ s|/| |g;

    my @bits = split /\s+/, $background;

    $background = join " ", grep {
      !$removable_bits{$_};
    } @bits;

    next if length $background == 0;

    my $genotype = $background_prop->feature();

    my $session = "UNKNOWN";

    if ($genotype->uniquename() =~ /^([0-9a-f]{8,})-genotype-\d+$/) {
      $session = $1;
    }

    my $line = qq|$session,"$orig_background","$background"|;

    next if $seen{$line};

    $seen{$line} = 1;

    $count++;

    print "$line\n";
  }

  return $count == 0;
}

1;
