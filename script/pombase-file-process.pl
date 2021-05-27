#!/usr/bin/perl -w

# driver for code that processes or fixes data files

use perl5i::2;
use Moose;

use Getopt::Long qw(:config pass_through);
use lib qw(lib);
use YAML qw(LoadFile);

sub usage
{
  die qq($0: needs five arguments:
  config_file   - the YAML format configuration file name
  process_type  - possibilities:
                    - "transfer-gaf-annotations": create a new GAF file from
                        an existing GAF file via 1-1 orthologs

usage:
  $0 <args>

  $0 <config_file> transfer-gaf-annotations \
    --source-organism-taxonid=<taxon_id_a> -
    --dest-organism-taxonid=<taxon_id_b> \
    --evidence-codes-to-keep=<comma_sep_list> \
    --ortholog-file=<orth_file> < org_a_annotations.gaf > org_b_annotations.gaf

);
}

if (@ARGV < 2) {
  usage();
}

my $config_file = shift;
my $process_type = shift;

use PomBase::Config;

my $config = PomBase::Config->new(file_name => $config_file);

my %process_modules = (
  'transfer-gaf-annotations' => 'PomBase::Chado::OrthologAnnotationTransfer',
);

my $process_module = $process_modules{$process_type};
my $processor;

if (defined $process_module) {
  $processor =
    eval qq{
require $process_module;
$process_module->new(config => \$config,
                     options => [\@ARGV]);
    };
  die "$@" if $@;
} else {
  die "unknown type to process: $process_type\n";
}

my $results = $processor->process();
