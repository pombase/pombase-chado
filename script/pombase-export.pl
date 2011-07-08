#!/usr/bin/perl -w

use perl5i::2;

use YAML qw(LoadFile);

use lib qw(lib);

if (@ARGV != 5) {
  die qq($0: needs fives arguments:
  retrieve_type - currently only "phenotypes"
  config_file   - the YAML format configuration file name
  database_name - the Chado database name
  username      - the database user name
  password      - the database password
);
}

my $retrieve_type = shift;
my $config_file = shift;
my $database = shift;
my $username = shift;
my $password = shift;

use PomBase::Chado;
my $chado = PomBase::Chado->db_connect($database, $username, $password);

my $config = LoadFile($config_file);

my %retrieve_modules = (
  phenotypes => 'PomBase::Retrieve::Phenotypes',
);

my $retrieve_module = $retrieve_modules{$retrieve_type};

if (defined $retrieve_module) {
  my $retriever =
    eval qq{
require $retrieve_module;
$retrieve_module->new(chado => \$chado, config => \$config);
};
  die "$@" if $@;

  my $results = $retriever->retrieve();

  while (my $row = $results->next()) {
    say join "\t", @$row;
  }
} else {
  die "unknown type to retrieve: $retrieve_type\n";
}
