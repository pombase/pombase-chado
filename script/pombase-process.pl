#!/usr/bin/perl -w

# driver for code that processes or fixes data in Chado, without needing
# external files

use strict;
use warnings;
use Carp;

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
                    - "go-filter-with-not": filter inferred annotations where
                           there is a non-inferred NOT annotation
                    - "go-filter-duplicate-assigner": remove redundancy due to
                           annotation assigned by multiple sources
                    - "update-allele-names": change "SPAC1234c.12delta" to
                           "abcdelta" if the gene now has a name
                    - "change-terms": change terms in annotations based on a
                           mapping file
                    - "add-reciprocal-ipi-annotations": add missing reciprocal
                           protein binding IPI annotations
                    - "transfer-names-and-products": transfer from one organism
                           to another
                    - "add-eco-evidence-codes": using a mapping file, add an ECO
                           evidence code as a feature_cvtermprop with prop type
                           "eco_evidence" based on the existing "evidence" prop
                    - "add-missing-allele-names": use the gene name and allele
                           description to name unnamed genes
  host          - the database server machine name
  database_name - the Chado database name
  username      - the database user name
  password      - the database password

usage:
  $0 <args>

  $0 <config_file> transfer-gaf-annotations \
    --source-organism-taxonid=<taxon_id_a> -
    --dest-organism-taxonid=<taxon_id_b> \
    --evidence-codes-to-keep=<comma_sep_list> \
    --terms-to-ignore=<comma_sep_list> \
    <host> <database_name> <username> <password> \
       < org_a_annotations.gaf > org_b_annotations.gaf

  $0 <config_file> go-filter-duplicate-assigner \
    --primary-assigner=<some_important_assigned_by> \
    --secondary_assigner=<less_important_assigned_by> \
    <host> <database_name> <username> <password>

  $0 <config_file> add-eco-evidence-codes \
    --eco-mapping-file=<file_path> \
    <host> <database_name> <username> <password>
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

if (!defined $password) {
  die "$0: not enough arguments";
  usage();
}

if (@ARGV > 0) {
  die "$0: no arguments";
  usage();
}

use PomBase::Chado;
use PomBase::Config;
use PomBase::Chado::IdCounter;

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);
my $guard = $chado->txn_scope_guard;

my $config = PomBase::Config->new(file_name => $config_file);

my $id_counter = PomBase::Chado::IdCounter->new(config => $config,
                                                chado => $chado);
$config->{id_counter} = $id_counter;

my %process_modules = (
  'go-filter' => 'PomBase::Chado::GOFilter',
  'go-filter-with-not' => 'PomBase::Chado::GOFilterWithNot',
  'go-filter-duplicate-assigner' => 'PomBase::Chado::GoFilterDuplicateAssigner',
  'update-allele-names' => 'PomBase::Chado::UpdateAlleleNames',
  'change-terms' => 'PomBase::Chado::ChangeTerms',
  'uniprot-ids-to-local' => 'PomBase::Chado::UniProtIDsToLocal',
  'add-reciprocal-ipi-annotations' => 'PomBase::Chado::AddReciprocalIPI',
  'transfer-names-and-products' => 'PomBase::Chado::TransferNamesAndProducts',
  'transfer-gaf-annotations' => 'PomBase::Chado::OrthologAnnotationTransfer',
  'add-eco-evidence-codes' => 'PomBase::Chado::AddEcoEvidenceCodes',
  'add-missing-allele-names' => 'PomBase::Chado::AddMissingAlleleNames',
);

my $process_module = $process_modules{$process_type};
my $processor;

if (defined $process_module) {
  $processor =
    eval qq{
require $process_module;
$process_module->new(chado => \$chado, config => \$config,
                    options => [\@options]);
    };
  die "$@" if $@;
} else {
  die "unknown type to process: $process_type\n";
}

my $results = $processor->process();

if ($verbose) {
  print $processor->results_summary($results);
}

$guard->commit unless $dry_run;
