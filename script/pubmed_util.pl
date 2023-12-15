#!/usr/bin/env perl

use strict;
use warnings;
use Carp;

use Getopt::Long;
use File::Basename;
use lib qw(lib);
use GDBM_File;
use Storable qw(thaw);
use JSON;

use PomBase::Config;
use PomBase::Chado;
use PomBase::Chado::PubmedUtil;

my $dry_run = 0;
my $do_fields = 0;
my $dump_json = 0;
my $organism_taxonid = undef;
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
                "dump-as-json:s" => \$dump_json,
                "organism-taxonid=s" => \$organism_taxonid,
                "help|h" => \$do_help,
                "verbose|v" => \$verbose)) {
  usage();
}

sub usage
{
  die "usage:
   $0 <config_file> <host> <database> <user> <password> <options> --add-missing-fields --organism-taxonid <taxonid>
 OR
   $0 <config_file> <host> <database> <user> <password> <options> --dump-as-json <pmid_id>

options:
  --add-missing-fields (or -f): access pubmed to add missing title, abstract,
          authors, etc. to publications in the publications table (pub)

  --dump-as-json: write the details about <pmid_id> as JSON to stdout
";
}

if ($do_help || !($do_fields || $dump_json) || @ARGV > 0) {
  usage();
}

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

tie my %pubmed_cache, 'GDBM_File', 'pubmed_cache.gdbm', &GDBM_WRCREAT, 0640;

if ($do_fields) {
  if (!defined $organism_taxonid || length $organism_taxonid == 0) {
    die "--add-missing-fields needs a --organism-taxonid argument\n";
  }

  my $guard = $chado->txn_scope_guard();

  my $pubmed_util = PomBase::Chado::PubmedUtil->new(chado => $chado, config => $config,
                                                    pubmed_cache => \%pubmed_cache);
  my ($missing_count, $loaded_count) =
    $pubmed_util->add_missing_fields(taxonid => $organism_taxonid);

  print "$missing_count publications have missing fields\n";
  print "details added for $loaded_count publications\n";

  $guard->commit() unless $dry_run;
}

if ($dump_json) {
  my $uniquename = $dump_json;
  my $raw_cached = $pubmed_cache{$uniquename};
  if (defined $raw_cached) {
    my $pub_details = thaw($raw_cached);

    my $json = JSON->new()->allow_nonref();

    print $json->encode($pub_details);
  } else {
    warn "$uniquename is not cached\n";
  }
}
