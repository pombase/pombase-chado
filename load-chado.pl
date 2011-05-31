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
use PomBase::Chado::EmblLoad;

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

my $embl_load = PomBase::Chado::EmblLoad->new(chado => $chado,
                                              verbose => $verbose,
                                              config => $config
                                            );
# load extra CVs, cvterms and dbxrefs
warn "loading genes ...\n" unless $quiet;
my $new_objects;

if (!$test) {
  $new_objects = PomBase::Load::init_objects($chado);
}

my %no_systematic_id_counts = ();

while (defined (my $file = shift)) {

  my $io = Bio::SeqIO->new(-file => $file, -format => "embl" );
  my $seq_obj = $io->next_seq;
  my $anno_collection = $seq_obj->annotation;

  for my $bioperl_feature ($seq_obj->get_SeqFeatures) {
    my $type = $bioperl_feature->primary_tag();

    if (!$bioperl_feature->has_tag("systematic_id")) {
      $no_systematic_id_counts{$type}++;
      next;
    }

    my @systematic_ids = $bioperl_feature->get_tag_values("systematic_id");

    if (@systematic_ids != 1) {
      my $systematic_id_count = scalar(@systematic_ids);
      warn "  expected 1 systematic_id, got $systematic_id_count, for:";
      $embl_load->dump_feature($bioperl_feature);
      exit(1);
    }

    my $systematic_id = $systematic_ids[0];

    warn "processing $type $systematic_id\n";

    my $pombe_gene = undef;

    try {
      $pombe_gene = $embl_load->find_chado_feature($systematic_id);
    } catch {
      warn "  no feature found for $type $systematic_id\n";
    };

    next if not defined $pombe_gene;

    if ($bioperl_feature->has_tag("controlled_curation")) {
      for my $value ($bioperl_feature->get_tag_values("controlled_curation")) {
        my %unused_quals = $embl_load->process_one_cc($pombe_gene, $bioperl_feature, $value);
        $embl_load->check_unused_quals($value, %unused_quals);
        warn "\n" if $verbose;
      }
    }

    if ($bioperl_feature->has_tag("GO")) {
      for my $value ($bioperl_feature->get_tag_values("GO")) {
        my %unused_quals = $embl_load->process_one_go_qual($pombe_gene, $bioperl_feature, $value);
        $embl_load->check_unused_quals($value, %unused_quals);
        warn "\n" if $verbose;
      }
    }

    if ($type eq 'CDS') {
      if ($bioperl_feature->has_tag("product")) {
        my @products = $bioperl_feature->get_tag_values("product");
        if (@products > 1) {
          warn "  $systematic_id has more than one product\n";
        } else {
          if (length $products[0] == 0) {
            warn "  zero length product for $systematic_id\n";
          }
        }
      } else {
        warn "  no product for $systematic_id\n";
      }
    }
  }
}

warn "counts of features that have no systematic_id, by type:\n";

for my $type_key (keys %no_systematic_id_counts) {
  warn "$type_key ", $no_systematic_id_counts{$type_key}, "\n";
}
warn "\n";

$guard->commit unless $dry_run;
