#!/usr/bin/perl -w

use perl5i::2;
use Moose;

open my $name_mismatches, '>', 'mismatches.txt' or die;
open my $unknown_term_names, '>', 'unknown_term_names.txt' or die;
open my $ortholog_problems, '>', 'ortholog_problems.txt' or die;
open my $qual_problems, '>', 'qualifier_problems.txt' or die;
open my $unknown_cv_names, '>', 'unknown_cv_names' or die;

my $prev_line = '';
my $gene = '';

while (defined (my $line = <>)) {
  if ($line =~ /ID in EMBL file/) {
    print $name_mismatches "$gene: $line";
  } else {
    if ($line =~ /found cvterm by ID/) {
      print $unknown_term_names "$gene: $line";
    } else {
      if ($line =~ /didn't process: /) {
        if ($prev_line =~ /ortholog.*not found/) {
          print $ortholog_problems "$gene: $line";
        } else {
          chomp $prev_line;
          chomp $line;
          print $qual_problems "$gene: $line  - error: $prev_line\n";
        }
      } else {
        if ($line =~ /CV name not recognised/) {
          print $unknown_cv_names "$gene: $line";
        } else {
          if ($line =~ /^processing (.*)/) {
            $gene = $1;
          }
        }
      }
    }
  }

  $prev_line = $line;
}
