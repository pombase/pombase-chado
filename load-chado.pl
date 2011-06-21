#!/usr/bin/perl -w

use perl5i::2;

use Bio::SeqIO;
use Bio::Chado::Schema;
use Memoize;
use Getopt::Long;
use YAML qw(LoadFile);

BEGIN {
  push @INC, 'lib';
};

use PomBase::Chado;
use PomBase::Load;
use PomBase::Chado::LoadFile;
use PomBase::Chado::QualifierLoad;
use PomBase::Chado::CheckLoad;

no stringification;

my $verbose = 0;
my $quiet = 0;
my $dry_run = 0;
my $test = 0;
my @mappings = ();

sub usage {
  die "$0 [-v] [-d] <embl_file> ...\n";
}

my %opts = ();

if (!GetOptions("verbose|v=s" => \$verbose,
                "dry-run|d=s" => \$dry_run,
                "quiet|q=s" => \$quiet,
                "test|t=s" => \$test,
                "mapping|m=s" => \@mappings)) {
  usage();
}

my $config_file = shift;
my $database = shift;

my $config = LoadFile($config_file);

my $chado = PomBase::Chado::connect($database, 'kmr44', 'kmr44');

my $guard = $chado->txn_scope_guard;

# load extra CVs, cvterms and dbxrefs
print "loading genes into $database ...\n" unless $quiet;

func read_mapping($file_name)
{
  my %ret = ();

  open my $file, '<', $file_name or die "$!: $file_name\n";

  <$file>;

  while (defined (my $line = <$file>)) {
    if ($line =~ /(.*?),\s*(.*?)\s+(\S+)$/) {
      $ret{$2} = $3;
    }
  }

  return \%ret;
}

func process_mappings(@mappings)
{
  return map {
    if (/(.*):(.*):(.*)/) {
      ($1, { new_name => $2, mapping => read_mapping($3) });
    } else {
      warn "unknown mapping: $_\n";
      usage();
    }
  } @mappings;
}

$config->{test_mode} = $test;
$config->{mappings} = {process_mappings(@mappings)};

my $organism = PomBase::Load::init_objects($chado, $config);

my @files = @ARGV;

while (defined (my $file = shift)) {
  my $load_file = PomBase::Chado::LoadFile->new(chado => $chado,
                                                verbose => $verbose,
                                                config => $config,
                                                organism => $organism);

  $load_file->process_file($file);
}

if ($test) {
  my $checker = PomBase::Chado::CheckLoad->new(chado => $chado,
                                               config => $config,
                                             );

  $checker->check();
}

$guard->commit unless $dry_run;
