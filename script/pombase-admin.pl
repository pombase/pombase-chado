#!/usr/bin/env perl

use strict;
use warnings;
use Carp;

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
  action        - see below
  host          - the database server machine name
  database_name - the Chado database name
  username      - the database user name
  password      - the database password

Actions:

  chado-init     - needs no extra arguments; adds initial cvterms an
                   dbxrefs for feature loading using the "cvs" section of
                   the config file

  add-chado-prop - add a value to the chadoprop table using an existing cvterm;
                   needs two extra arguments: prop_type_name and prop_value
                   eg. "goa_version" and "218"
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

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

my $guard = $chado->txn_scope_guard;

my $config = PomBase::Config->new(file_name => $config_file);

my $id_counter = PomBase::Chado::IdCounter->new(config => $config,
                                                chado => $chado);
$config->{id_counter} = $id_counter;

if ($action eq 'chado-init') {
  PomBase::Chado::InitUtil::init_objects($chado, $config);
}

if ($action eq 'add-chado-prop') {
  if (@ARGV < 2) {
    warn "not enough arguments\n";
    usage();
  }

  my $prop_name = shift;
  my $prop_value = shift;

  my $type_cvterm = $chado->resultset('Cv::Cvterm')
    ->find({ name => $prop_name });

  if (!defined $type_cvterm) {
    die "can't find cvterm for $prop_name\n";
  }

  $chado->resultset('Cv::Chadoprop')
    ->create({ type_id => $type_cvterm->cvterm_id(),
               value => $prop_value });
}

$guard->commit unless $dry_run;
