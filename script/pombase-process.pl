#!/usr/bin/perl -w

use perl5i::2;
use Moose;

use Getopt::Long qw(:config pass_through);
use lib qw(lib);
use YAML qw(LoadFile);

my $dry_run = 0;
my $verbose = 0;

if (!GetOptions("dry-run|d" => \$dry_run,
                "verbose|v" => \$verbose)) {
  usage();
}

sub usage
{
  die qq($0: needs five arguments:
  config_file   - the YAML format configuration file name
  process_type  - possibilities:
                    - "go-filter": filter redundant GO annotations
  host          - the database server machine name
  database_name - the Chado database name
  username      - the database user name
  password      - the database password

usage:
  $0 <args>
);
}

if (@ARGV < 5) {
  usage();
}

my $config_file = shift;
my $process_type = shift;

my @options = ();
while ($ARGV[0] =~ /^-/) {
  push @options, shift;
}

my $host = shift;
my $database = shift;
my $username = shift;
my $password = shift;

if (!defined $password || @ARGV > 0) {
  die "$0: not enough arguments";
  usage();
}

use PomBase::Chado;
use PomBase::Chado::IdCounter;

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);
my $guard = $chado->txn_scope_guard;
my $config = LoadFile($config_file);

my %process_modules = (
  'go-filter' => 'PomBase::Chado::GOFilter',
);

my $process_module = $process_modules{$process_type};
my $processor;

if (defined $process_module) {
  $process =
    eval qq{
require $process_module;
$process_module->new(chado => \$chado, config => \$config,
                    options => [\@options]);
    };
  die "$@" if $@;
} else {
  die "unknown type to process: $process_type\n";
}

my $results = $process->process($fh);

if ($verbose) {
  print $process->results_summary($results);
}

$guard->commit unless $dry_run;
