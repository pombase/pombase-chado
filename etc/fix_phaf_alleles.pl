#!/usr/bin/env perl

# Use the output of Manu's code to find and fix allele descriptions
# and types
#
# See: https://github.com/pombase/canto/issues/2689
#
# Run in the pombase-chado directory like:
#   ./etc/fix_phaf_alleles.pl ALLELE_FIX_FILE PHAF_FILE > NEW_PHAF_FILE

use strict;
use warnings;
use Carp;

use Text::CSV;


sub usage {
  die "needs twos args\n
  - the file of allele fixes
  - a PHAF file\n";
}

my $change_file = shift;

if (!defined $change_file) {
  usage();
}

my $phaf_file = shift;

if (!defined $phaf_file) {
  usage();
}


open my $change_fh, '<', $change_file or die;

my $change_tsv = Text::CSV->new({ sep_char => "\t", binary => 1,
                                  quote_char => undef,
                                  auto_diag => 1, strict => 1 });

$change_tsv->column_names($change_tsv->getline($change_fh));

my %change_map = ();

while (my $row = $change_tsv->getline_hr($change_fh)) {
  if (defined $row->{solution_index} && $row->{solution_index} ne '') {
    next;
  }

  if (exists $change_map{$row->{allele_name}}) {
    warn "ignoring duplicate allele_name: ", $row->{allele_name}, "\n";
    next;
  }

  $change_map{$row->{allele_name}} = $row;
}

close $change_fh;


open my $phaf_fh, '<', $phaf_file or die;

while (defined (my $line = <$phaf_fh>)) {
  print $line;
  if ($line =~ /^gene/i) {
    # end of headers
    last;
  }
}

while (defined (my $line = <$phaf_fh>)) {
  my @parts = split /\t/, $line;

  my $name_ref = \$parts[8];
  my $old_name = $$name_ref;

  if (!$old_name) {
    print $line;
    next;
  }

  my $changes = $change_map{$old_name};

  if (defined $changes) {
    my $description_ref = \$parts[2];
    my $type_ref = \$parts[10];

    my $new_description = $changes->{change_description_to};

    if ($new_description) {
      my $old_description = $$description_ref // '';

      if ($old_description ne $changes->{allele_description} &&
          $old_description ne '' && lc $old_description ne 'unknown') {
        warn qq|$phaf_file: for "$old_name" description in PHAF file doesn't match file: "$old_description" vs "|,
          $changes->{allele_description}, qq|"\n|;
      } else {
        warn qq|$phaf_file: $old_name: changing description "$old_description" to "$new_description"\n|;
        $$description_ref = $new_description;
      }
    }

    my $new_type = $changes->{change_type_to};

    if ($new_type) {
      my $old_type = $$type_ref;
      $old_type =~ s/ /_/g;

      $new_type = 'other' if $new_type eq 'amino_acid_other';

      if (defined $changes->{allele_type} && $old_type ne $changes->{allele_type}) {
        warn qq|$phaf_file: for "$old_name", type in PHAF file doesn't match mapping file "$old_type" vs "|,
          $changes->{allele_type}, qq|"\n|;
      } else {
        warn qq|$phaf_file: $old_name: changing type "$old_type" to "$new_type"\n|;
        $$type_ref = $new_type;
      }
    }

    my $new_name = $changes->{change_name_to};

    if ($new_name) {
      my $old_name = $$name_ref;
      warn qq|$phaf_file: $old_name: changing to "$new_name"\n|;

      $$name_ref = $new_name;

      if ($old_name) {
        if ($parts[9]) {
          $parts[9] .= "|$old_name";
        } else {
          $parts[9] = "$old_name";
        }
      }
    }

    $line = join "\t", @parts;
  }

  print $line;
}


close $phaf_fh;
