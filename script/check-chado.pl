#!/usr/bin/perl -w

use perl5i::2;

use Getopt::Std;
use Module::Find;
use YAML qw(LoadFile);

BEGIN {
  push @INC, 'lib';
};

use PomBase::Check;

if (@ARGV != 5) {
  die "$0: needs five arguments:
  eg. $0 config_file database_host database_name user_name password\n";
}

my $config_file = shift;
my $host = shift;
my $database = shift;
my $username = shift;
my $password = shift;

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

my $config = LoadFile($config_file);

my $check = PomBase::Check->new(chado => $chado, config => $config);

$check->run();
