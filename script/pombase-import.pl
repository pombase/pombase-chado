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
  die qq($0: needs six arguments:
  config_file   - the YAML format configuration file name
  import_type   - possibilities:
                    - "biogrid": interaction data in BioGRID BioTAB 2.0 format
                    - "gaf": GO gene association file format
                    - "pomcur": curation data in curation tool YAML format
                    - "orthologs": a file of orthologs
  host          - the database server machine name
  database_name - the Chado database name
  username      - the database user name
  password      - the database password

The orthologs file should be tab delimited with two columns.  The
first column should contain an identifier.  The second column should
contain the identifier of one or more orthologs, separated by commas.

The orthologs type has three required arguments:
  --publication        - the PubMed ID to add as dbxref
  --organism_1_taxonid - the taxon ID of genes in column 1
  --organism_2_taxonid - taxon ID of genes in column 2
and one optional argument:
  --swap_direction     - if present the column 1 gene with be used as
                         the object of the feature_relationship,
                         rather than the subject

usage:
  $0 <args> < input_file
);

}

if (@ARGV < 6) {
  usage();
}

my $config_file = shift;
my $import_type = shift;

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

my $id_counter = PomBase::Chado::IdCounter->new(config => $config,
                                                chado => $chado);
$config->{id_counter} = $id_counter;

my %import_modules = (
  biogrid => 'PomBase::Import::BioGRID',
  gaf => 'PomBase::Import::GeneAssociationFile',
  pomcur => 'PomBase::Import::PomCur',
  orthologs => 'PomBase::Import::Orthologs',
  quantitative => 'PomBase::Import::Quantitative',
);

my $import_module = $import_modules{$import_type};
my $importer;

if (defined $import_module) {
  $importer =
    eval qq{
require $import_module;
$import_module->new(chado => \$chado, config => \$config,
                    verbose => \$verbose,
                    options => [\@options]);
    };
  die "$@" if $@;
} else {
  die "unknown type to import: $import_type\n";
}

open my $fh, '<-' or die;

my $results = $importer->load($fh);

if ($verbose) {
  print $importer->results_summary($results);
}

$guard->commit unless $dry_run;
