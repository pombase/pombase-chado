#!/usr/bin/perl -w

use perl5i::2;

use YAML qw(LoadFile);

use lib qw(lib);

sub usage
{
  die qq($0: needs six arguments:
  config_file   - the YAML format configuration file name
  export_type - eg. "phenotypes", "orthologs", "ontology", "gaf"
  host          - the machine hosting the database
  database_name - the Chado database name
  username      - the database user name
  password      - the database password

Options for the "gaf" export type:
    --filter-by-term=<term> - only export annotations using the given term or
                              its descendents
    --filter-term-by-sql=<sql> - filter rows by cvterm_id, this should be a
                                 valid SQL that returns cvterm_id rows.
    --organism-taxon-id=<id> - NCBI taxon ID of the annotations to export
);
}

if (@ARGV < 6) {
  usage();
}

my $config_file = shift;
my $retrieve_type = shift;

my @options = ();
while ($ARGV[0] =~ /^-/) {
  push @options, shift;
}

my $host = shift;
my $database = shift;
my $username = shift;
my $password = shift;

use PomBase::Chado;
use PomBase::Config;

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

if (! -e $config_file) {
  die "can't load config from $config_file: file not found\n";
}

my $config = PomBase::Config->new(file_name => $config_file);

if (!defined $config) {
  die "can't load config from $config_file: file is empty\n";
}

my %retrieve_modules = (
  phenotypes => 'PomBase::Retrieve::Phenotypes',
  orthologs => 'PomBase::Retrieve::Orthologs',
  interactions => 'PomBase::Retrieve::Interactions',
  ontology => 'PomBase::Retrieve::Ontology',
  gaf => 'PomBase::Retrieve::GeneAssociationFile',
  phaf => 'PomBase::Retrieve::PhenotypeAnnotationFormat',
  'go-physical-interactions' => 'PomBase::Retrieve::GOPhysicalInteractions',
  'go-substrates' => 'PomBase::Retrieve::GOSubstrates',
);

my $retrieve_module = $retrieve_modules{$retrieve_type};

if (defined $retrieve_module) {
  my $retriever =
    eval qq{
require $retrieve_module;
$retrieve_module->new(chado => \$chado, config => \$config,
                      options => [\@options]);
};
  die "$@" if $@;

  print $retriever->header();

  my $results = $retriever->retrieve();

  while (my $data = $results->next()) {
    print $retriever->format_result($data), "\n";
  }
} else {
  die "unknown type to retrieve: $retrieve_type\n";
}
