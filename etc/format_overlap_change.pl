#!/usr/bin/env perl

# Read a diff of the overlapping nodes file:
# pombe-embl/supporting_files/nightly_load_results/overlapping_nodes.tsv
# and display a list of joins that have been removed

use strict;
use warnings;

use Text::CSV;

my $csv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

die "needs an argument\n" unless @ARGV > 0;

my $date = shift;
my $file_name = shift;

open my $fh, '<', $file_name or die "can't open $file_name\n";

$csv->column_names($csv->getline($fh));

my %added_joins = ();
my %removed_joins = ();

while (defined (my $line = $fh->getline())) {
  my $added_removed;

  if ($line =~ /^([\-+])(.*)/) {
    $added_removed = $1;
    $line = $2;
  } else {
    die;
  }

  if (!$csv->parse($line)) {
    die "Parse error at line $.: ", $csv->error_input(), "\n";
  }

  my %columns = ();
  my @fields = $csv->fields();
  @columns{ $csv->column_names() } = @fields;

  my @model_ids =
    map { s/^gomodel://; $_ }
    split /\+/, $columns{model_ids};

  @model_ids = sort @model_ids;

  for my $model_id_1_idx (0..@model_ids-1) {
  my $model_id_1 = $model_ids[$model_id_1_idx];
    for my $model_id_2_idx ($model_id_1_idx+1..@model_ids-1){
      my $model_id_2 = $model_ids[$model_id_2_idx];

      my $key = "$model_id_1+$model_id_2";

      if ($added_removed eq '+') {
        $added_joins{$key} = 1;
      } else {
        $removed_joins{$key} = 1;
      }
    }
  }
}


my @added_list = ();
for my $added_id (keys %added_joins) {
  if (!exists $removed_joins{$added_id}) {
    push @added_list, $added_id
  }
}

my @removed_list = ();
for my $removed_id (keys %removed_joins) {
  if (!exists $added_joins{$removed_id}) {
    push @removed_list, $removed_id
  }
}

if (@removed_list) {
  print "Removed joins $date:\n\n";
  for my $removed_ids (@removed_list) {
    print " https://www.pombase.org/gocam/pombase-view/docs/$removed_ids\n";
  }

  print "\n";
}

