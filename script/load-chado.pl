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
use PomBase::Chado::IdCounter;
use PomBase::Chado::ExtensionProcessor;
use PomBase::Chado::ParalogProcessor;

my $verbose = 0;
my $quiet = 0;
my $dry_run = 0;
my $test = 0;
my @obsolete_term_mapping_files = ();
my $gene_ex_qualifiers;
my @mappings = ();

sub usage {
  die "$0 [-v] [-d] <embl_file> ...\n";
}

if (!GetOptions("verbose|v" => \$verbose,
                "dry-run|d" => \$dry_run,
                "quiet|q" => \$quiet,
                "test|t" => \$test,
                "obsolete-term-map=s" => \@obsolete_term_mapping_files,
                "gene-ex-qualifiers=s" => \$gene_ex_qualifiers,
                "mapping|m=s" => \@mappings)) {
  usage();
}

my $config_file = shift;
my $host = shift;
my $database = shift;
my $user = shift;
my $password = shift;

my $config = LoadFile($config_file);

my $chado = PomBase::Chado::db_connect($host, $database, $user, $password);

my $guard = $chado->txn_scope_guard;

# load extra CVs, cvterms and dbxrefs
print "loading genes into $database ...\n" unless $quiet;

func read_mapping($old_name, $file_name)
{
  my %ret = ();

  open my $file, '<', $file_name or die "$!: $file_name\n";

  while (defined (my $line = <$file>)) {
    chomp;

    if ($line =~ /$old_name,\s*(.*?)\s+(\S+)$/) {
      $ret{$1} = $2;
    } else {
      if ($line =~ /\s*(.*?)\s+(\S+)$/) {
        $ret{$1} = $2;
      } else {
        warn "unknown format for line from mapping file: $line";
      }
    }
  }

  return \%ret;
}

func process_mappings(@mappings)
{
  return map {
    if (/(.*):(.*):(.*)/) {
      ($1, { new_name => $2, mapping => read_mapping($1, $3) });
    } else {
      warn "unknown mapping: $_\n";
      usage();
    }
  } @mappings;
}

$config->{test_mode} = $test;
$config->{mappings} = {process_mappings(@mappings)};

func read_obsolete_term_mapping($file_name)
{
  my %ret = ();

  open my $file, '<', $file_name or die "$!: $file_name\n";

  while (defined (my $line = <$file>)) {
    chomp $line;

    next if $line =~ /^!/;
    my @bits = split /\t/, $line;
    $ret{$bits[1]} = $bits[0];
  }

  close $file;

  return %ret;
}

func process_obsolete_term_mapping_files(@obsolete_term_files)
{
  return (map { read_obsolete_term_mapping($_) } @obsolete_term_files);
}

$config->{obsolete_term_mapping} = {
  process_obsolete_term_mapping_files(@obsolete_term_mapping_files)
};

$config->{target_quals} = {};

func read_gene_ex_qualifiers($gene_ex_qualifiers) {
  open my $fh, '<', $gene_ex_qualifiers
    or die "can't opn $gene_ex_qualifiers: $!";

  my @ret_val = ();

  while (defined (my $line = <$fh>)) {
    next if $line =~ /^!/;

    chomp $line;

    push @ret_val, $line;
  }

  close $fh;

  return \@ret_val;
}

$config->{gene_ex_qualifiers} =
  read_gene_ex_qualifiers($gene_ex_qualifiers);

for my $allowed_unknown_term_names_file (@{$config->{allowed_unknown_term_names_files}}) {
  open my $unknown_names, '<', $allowed_unknown_term_names_file or die;
  while (defined (my $line = <$unknown_names>)) {
    chomp $line;
    if ($line =~ /but name doesn't match any cvterm: (\S+)/) {
      $config->{allowed_unknown_term_names}->{$1} = 1;
    } else {
      if ($line =~ /^GO:\d+$/) {
        $config->{allowed_unknown_term_names}->{$line} = 1;
      } else {
        die "can't parse: $line";
      }
    }
  }
  close $unknown_names;
}


for my $allowed_term_mismatches_file (@{$config->{allowed_term_mismatches_files}}) {

open my $mismatches, '<', $allowed_term_mismatches_file or die;
while (defined (my $line = <$mismatches>)) {
  if ($line =~ /\S+ (\S+?)(?:\.\d)?:\s+ID in EMBL file \((\S+)\) doesn't match ID in Chado \(\S+\) for EMBL term name (.*)\s+\(Chado term name: .*\)\t?(.*)/) {
    my $gene = $1;
    my $embl_id = $2;
    my $embl_name = $3;
    my $winner = $4;

    $embl_id =~ s/\s+$//;
    $embl_name =~ s/\s+$//;

    next unless $winner =~ /^(ID|name)$/i;

    push @{$config->{allowed_term_mismatches}->{$gene}}, {
      embl_id => $embl_id,
      embl_name => $embl_name,
      winner => $winner,
    };
  } else {
    if ($line !~ /warning line/) {
      warn "can't parse: $line";
    }
  }
}
close $mismatches;
}

my $id_counter = PomBase::Chado::IdCounter->new(chado => $chado,
                                                config => $config);

$config->{id_counter} = $id_counter;

my $organism = PomBase::Load::init_objects($chado, $config);

my @files = @ARGV;

while (defined (my $file = shift)) {
  my $load_file = PomBase::Chado::LoadFile->new(chado => $chado,
                                                verbose => $verbose,
                                                config => $config,
                                                organism => $organism);

  $load_file->process_file($file);
}

if(0) {
# populate the phylonode table
my $phylotree = $chado->resultset('Phylogeny::Phylotree')->create(
  {
    name => 'org_hierarchy',
    dbxref => $chado->resultset('General::Dbxref')
      ->find({ accession => 'local:null' }),
  }
);

my $phylo_rs = $chado->resultset('Phylogeny::Phylonode');

my $phylonode_id = 0;
my @phylonodes =
  qw'root Eukaryota Fungi Dikarya Ascomycota Taphrinomycotina
     Schizosaccharomycetes Schizosaccharomycetales Schizosaccharomycetaceae
     Schizosaccharomyces';

for (my $i = 0; $i < @phylonodes; $i++) {
  $phylo_rs->create({ phylonode_id => $i++, left_id => $i,
                      right_id => $i, distance => scalar(@phylonodes) - $i });
}
}

my $extension_processor =
  PomBase::Chado::ExtensionProcessor->new(chado => $chado,
                                          config => $config,
                                          verbose => $verbose,
                                          id_counter => $id_counter);

my $post_process_data = $config->{post_process};

$extension_processor->process($post_process_data,
                              $config->{target_quals}->{is},
                              $config->{target_quals}->{of});

my $paralog_processor =
  PomBase::Chado::ParalogProcessor->new(chado => $chado,
                                        config => $config,
                                        verbose => $verbose);
my $paralog_data = $config->{paralogs};
$paralog_processor->store_all_paralogs($paralog_data);

my $checker = PomBase::Chado::CheckLoad->new(chado => $chado,
                                             config => $config,
                                             verbose => $verbose,
                                             );

warn "counts of unused qualifiers:\n";
while (my ($qual, $count) = each %{$config->{stats}->{unused_qualifiers}}) {
  warn "  $qual: $count\n";
}

if ($test) {
  $checker->check();
}
$guard->commit unless $dry_run;
