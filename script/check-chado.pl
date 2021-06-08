#!/usr/bin/perl -w

use strict;
use warnings;
use Carp;


use Getopt::Std;
use Module::Find;
use YAML qw(LoadFile);
use JSON;

BEGIN {
  push @INC, 'lib';
};

use PomBase::Check;
use PomBase::Config;

if (@ARGV != 6) {
  die "$0: needs six arguments:
  eg. $0 config_file website_config database_host database_name user_name password\n";
}

my $config_file = shift;
my $website_config_filename = shift;
my $host = shift;
my $database = shift;
my $username = shift;
my $password = shift;

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

my $config = PomBase::Config->new(file_name => $config_file);

open my $website_config_fh, '<', $website_config_filename or die;
my $website_config_text = '';
{
  local $/ = undef;
  $website_config_text = <$website_config_fh>;
}

my $website_config = JSON->new()->decode($website_config_text);

my $check = PomBase::Check->new(chado => $chado, config => $config,
                                website_config => $website_config);

exit $check->run();
