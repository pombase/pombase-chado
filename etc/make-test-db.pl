#!/usr/bin/perl -w

use perl5i::2;
use Moose;

my $max = -1;

open my $psql, 'psql -l|' or die;

while (defined (my $line = <$psql>)) {
  if ($line =~ /load-test-(\d+)/) {
    if ($1 > $max) {
      $max = $1;
    }
  }
}

close $psql;

my $new_num = $max + 1;

my $new_db_name = "load-test-$new_num";

print "creating new database\n";

system "createdb -T pombase-chado-base-2011-06-17 $new_db_name";

use IO::All;

$new_db_name > io('/tmp/new_test_db');

print "new database name: $new_db_name\n";
