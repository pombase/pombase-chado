#!/usr/bin/env perl

use strict;
use warnings;
use Carp;

use Getopt::Long;
use File::Basename;
use lib qw(lib);

use PomBase::Config;
use PomBase::Chado;
use PomBase::Chado::PubmedUtil;

my $dry_run = 0;
my $do_fields = 0;
my $do_help = 0;
my $verbose = 0;

if (@ARGV < 6) {
  usage();
}

my $config_file = shift;
my $config = PomBase::Config->new(file_name => $config_file);

my $host = shift;
my $database = shift;
my $username = shift;
my $password = shift;

if (!GetOptions("dry-run|d" => \$dry_run,
                "add-missing-fields|f" => \$do_fields,
                "help|h" => \$do_help,
                "verbose|v" => \$verbose)) {
  usage();
}

sub usage
{
  die "$0: needs one argument:
  --add-missing-fields (or -f): access pubmed to add missing title, abstract,
          authors, etc. to publications in the publications table (pub)
";
}

if ($do_help || !$do_fields || @ARGV > 0) {
  usage();
}

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

my $guard = $chado->txn_scope_guard();

my $result = GetOptions ("add-missing-fields|f" => \$do_fields,
                         "help|h" => \$do_help);

if ($do_fields) {
  my $pubmed_util = PomBase::Chado::PubmedUtil->new(chado => $chado, config => $config);
  my $count = $pubmed_util->add_missing_fields();

  print "added missing fields to $count publications\n";
}

$guard->commit() unless $dry_run;
