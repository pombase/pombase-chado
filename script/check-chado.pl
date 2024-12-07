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

my $query_only = 0;

if (@ARGV != 9) {
  die <<"EOF";
$0: needs eight arguments:
  eg. $0 config_file config_field website_config xref_config database_host database_name user_name password output_prefix

  - reads queries from the config file
  - run each query
  - write output to separate log files with the given output_prefix

By default, return a zero exit code only if all queries return zero rows

If the no_fail flag is set in the configuration, always exit with 0
EOF

}

my $config_file = shift;
my $config_field = shift;
my $website_config_filename = shift;
my $xref_config_filename = shift;
my $host = shift;
my $database = shift;
my $username = shift;
my $password = shift;
my $output_prefix = shift;

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

my $config = PomBase::Config->new(file_name => $config_file);

open my $website_config_fh, '<', $website_config_filename or
  die "can't open $website_config_filename: $!\n";

my $website_config_text = '';
{
  local $/ = undef;
  $website_config_text = <$website_config_fh>;
}

my $website_config = JSON->new()->decode($website_config_text);

open my $xref_config_fh, '<', $xref_config_filename or
  die "can't open $xref_config_filename: $!\n";

my $xref_config_text = '';
{
  local $/ = undef;
  $xref_config_text = <$xref_config_fh>;
}

my $xref_config = JSON->new()->decode($xref_config_text);



my $check = PomBase::Check->new(chado => $chado, config => $config,
                                config_field => $config_field,
                                output_prefix => $output_prefix,
                                website_config => $website_config,
                                xref_config => $xref_config);

exit $check->run();
