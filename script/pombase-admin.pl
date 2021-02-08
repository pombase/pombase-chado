#!/usr/bin/env perl

use perl5i::2;
use Moose;

use Getopt::Long qw(:config pass_through);
use lib qw(lib);

use PomBase::Config;
use PomBase::Chado;
use PomBase::Chado::IdCounter;
use PomBase::Chado::InitUtil;

my $dry_run = 0;

sub usage
{
  die qq(
usage:
  $0 <args> < input_file

Six arguments are always required:
  config_file   - the YAML format configuration file name
  action        - currently must be "chado-init" which adds initial cvterms
                  and dbxrefs for feature loading using the "cvs" section of
                  the config file
  host          - the database server machine name
  database_name - the Chado database name
  username      - the database user name
  password      - the database password
);

}

if (!GetOptions("dry-run|d" => \$dry_run)) {
  usage();
}

if (@ARGV < 6) {
  usage();
}

my $config_file = shift;
my $action = shift;

my @options = ();
while (@ARGV && $ARGV[0] =~ /^-/) {
  push @options, shift;
}

my $host = shift;
my $database = shift;
my $username = shift;
my $password = shift;

if (@ARGV) {
  warn "too many arguments\n";
  usage();
}

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

my $guard = $chado->txn_scope_guard;

my $config = PomBase::Config->new(file_name => $config_file);

my $id_counter = PomBase::Chado::IdCounter->new(config => $config,
                                                chado => $chado);
$config->{id_counter} = $id_counter;

if ($action eq 'chado-init') {
  PomBase::Chado::InitUtil::init_objects($chado, $config);
}

$guard->commit unless $dry_run;
