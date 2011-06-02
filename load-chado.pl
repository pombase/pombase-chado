#!/usr/bin/perl -w

use perl5i::2;

use Bio::SeqIO;
use Bio::Chado::Schema;
use Memoize;
use Getopt::Std;
use YAML qw(LoadFile);

BEGIN {
  push @INC, 'lib';
};

use PomBase::Chado;
use PomBase::Load;
use PomBase::Chado::LoadFile;
use PomBase::Chado::QualifierLoad;

my $verbose = 0;
my $quiet = 0;
my $dry_run = 0;
my $test = 0;

sub usage {
  die "$0 [-v] [-d] <embl_file> ...\n";
}

my %opts = ();

if (!getopts('vdqt', \%opts)) {
  usage();
}

if ($opts{v}) {
  $verbose = 1;
}
if ($opts{d}) {
  $dry_run = 1;
}
if ($opts{t}) {
  $test = 1;
}

my $config_file = shift;
my $database = shift;

my $config = LoadFile($config_file);

my $chado = PomBase::Chado::connect($database, 'kmr44', 'kmr44');

my $guard = $chado->txn_scope_guard;

# load extra CVs, cvterms and dbxrefs
print "loading genes ...\n" unless $quiet;

my $organism = PomBase::Load::init_objects($chado);

while (defined (my $file = shift)) {
  my $load_file = PomBase::Chado::LoadFile->new(chado => $chado,
                                                verbose => $verbose,
                                                config => $config,
                                                organism => $organism);

  $load_file->process_file($file);
}

$guard->commit unless $dry_run;
