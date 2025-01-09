#!/usr/bin/perl -w

use strict;
use warnings;
use Carp;

use Moose;

use Getopt::Long qw(:config pass_through);
use lib qw(lib);
use utf8::all;

my $dry_run = 0;
my $verbose = 0;

if (!GetOptions("dry-run|d" => \$dry_run,
                "verbose|v" => \$verbose)) {
  usage();
}

my %input_types = (
  organisms => 'PomBase::Import::Organisms',
  features => 'PomBase::Import::Features',
  biogrid => 'PomBase::Import::BioGRID',
  gaf => 'PomBase::Import::GeneAssociationFile',
  'generic-annotation' => 'PomBase::Import::GenericAnnotation',
  'generic-property' => 'PomBase::Import::GenericProperty',
  'generic-synonym' => 'PomBase::Import::GenericSynonym',
  'generic-feature-pub' => 'PomBase::Import::GenericFeaturePub',
  'generic-feature-name' => 'PomBase::Import::GenericFeatureName',
  'generic-cvtermprop' => 'PomBase::Import::GenericCvtermprop',
  'canto-json' => 'PomBase::Import::Canto',
  orthologs => 'PomBase::Import::Orthologs',
  paralogs => 'PomBase::Import::Paralogs',
  quantitative => 'PomBase::Import::Quantitative',
  qualitative => 'PomBase::Import::Qualitative',
  modification => 'PomBase::Import::Modification',
  'monarch-disease' => 'PomBase::Import::MonarchDisease',
  'phenotype-annotation' => 'PomBase::Import::PhenotypeAnnotation',
  'references-file' => 'PomBase::Import::ReferencesFile',
  'kegg-pathway' => 'PomBase::Import::KEGGMapping',
  'names-and-products' => 'PomBase::Import::NameAndProduct',
  'go-cam-json' => 'PomBase::Import::GoCamJson',
);

sub usage
{
  my $input_type_names = join "\n", map { "  $_" } keys %input_types;

  die qq(
usage:
  $0 <args> < input_file

Six arguments are always required:
  config_file   - the YAML format configuration file name
  import_type   - possibilities:
                    - "biogrid": interaction data in BioGRID BioTAB 2.0 format
                    - "gaf": GO gene association file format
                    - "canto-json": curation data in Canto YAML format
                    - "orthologs": a file of orthologs
  host          - the database server machine name
  database_name - the Chado database name
  username      - the database user name
  password      - the database password

Possible values for input_type are:
$input_type_names

Options specific to an input type should come straight after the input_type
argument.

eg.
  $0 config.yaml canto-json --organism-taxon=4896 --db-prefix=PomBase localhost dbname user pass < in_file.json

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

The canto type has two mandatory arguments:
  --organism-taxonid  - the NCBI taxon ID of the organism to load, which
                        must be stored in an organismprop in Chado with
                        the property type "taxon_id"
  --db-prefix         - the prefix to use when a gene identifier is stored
                        in a Chado property (eg. the "with" field of an IPI)
);

}

if (@ARGV < 6) {
  usage();
}

my $config_file = shift;
my $import_type = shift;

my @options = ();
while (@ARGV && $ARGV[0] =~ /^-/) {
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
  die "$0: too many arguments";
  usage();
}

use PomBase::Chado;
use PomBase::Chado::IdCounter;
use PomBase::Config;

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

my $guard = $chado->txn_scope_guard;

my $config = PomBase::Config->new(file_name => $config_file);

my $id_counter = PomBase::Chado::IdCounter->new(config => $config,
                                                chado => $chado);
$config->{id_counter} = $id_counter;

my $import_module = $input_types{$import_type};
my $importer;

if (defined $import_module) {
  $importer =
    eval qq{
require $import_module;
$import_module->new(chado => \$chado, config => \$config,
                    verbose => \$verbose,
                    options => [\@options]);
    };
  die "import failed: $@" if $@;
} else {
  die "unknown type to import: $import_type\n";
}

open my $fh, '<-' or die;

my $results = $importer->load($fh);

if ($verbose) {
  print $importer->results_summary($results);
}

$guard->commit unless $dry_run;
