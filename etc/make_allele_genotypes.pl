#!/usr/bin/env perl

# add a genotype feature for each allele that isn't already part of a genotype

use perl5i::2;
use Moose;

use Getopt::Long qw(:config pass_through);
use lib qw(lib);

my $dry_run = 0;
my $verbose = 0;

if (!GetOptions("dry-run|d" => \$dry_run,
                "verbose|v" => \$verbose)) {
  usage();
}

sub usage
{
  die qq(
usage:
  $0 <args> < input_file

Args:
  host          - the database server machine name
  database_name - the Chado database name
  username      - the database user name
  password      - the database password
);

}

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
  die "$0: too many arguments";
  usage();
}

use PomBase::Chado;
use PomBase::Chado::IdCounter;

my $chado = PomBase::Chado::db_connect($host, $database, $username, $password);

my $guard = $chado->txn_scope_guard;

my $allele_prop_rs =
  $chado->resultset('Sequence::Featureprop')
    ->search({ 'type.name' => 'allele' },
             { join => { feature => 'type' },
               prefetch => 'type' });

my %allele_props = ();

while (defined (my $prop = $allele_prop_rs->next())) {
  $allele_props{$prop->feature_id()}->{$prop->type()->name()} = $prop->value();
}

my $allele_rs =
  $chado->resultset('Sequence::Feature')->search({ 'type.name' => 'allele' },
                                                 { join => 'type' });

my %alleles = ();

while (defined (my $allele = $allele_rs->next())) {
  $alleles{$allele->feature_id()} = { obj => $allele,
                                      allele_type => $allele_props{$allele->feature_id()}->{allele_type},
                                      canto_session => $allele_props{$allele->feature_id()}->{canto_session},
                                      description => $allele_props{$allele->feature_id()}->{description} };
}

my $rel_rs =
  $chado->resultset('Sequence::FeatureRelationship')->search(
    {
      'me.subject_id' => {
        -in => $allele_rs->get_column('feature_id')->as_query()
      },
      'type.name' => 'part_of',
    },
    {
      join => ['subject', 'object', 'type'],
      prefetch => ['object', 'subject'],
    });

while (defined (my $rel = $rel_rs->next())) {
  # don't make a genotype for alleles that are part of one already
  delete $alleles{$rel->subject_id()};
}

my $genotype_rs =
  $chado->resultset('Sequence::Feature')->search(
    {
      'type.name' => 'genotype'
    },
    {
      join => 'type',
    });

my $uniquename_prefix = 'pombase-genotype-';
my $name_prefix = 'h+ ';
my $max_id = 0;

while (defined (my $genotype = $genotype_rs->next())) {
  if ($genotype->uniquename() =~ /^$uniquename_prefix(\d+)$/) {
    if ($1 > $max_id) {
      $max_id = $1;
    }
  }
}

my $part_of = $chado->resultset('Cv::Cvterm')
  ->find({ 'me.name' => 'part_of',
           'cv.name' => 'relationship',
         },
         {
           join => 'cv',
         });

my $genotype_term = $chado->resultset('Cv::Cvterm')
  ->find({ 'me.name' => 'genotype',
           'cv.name' => 'sequence',
         },
         {
           join => 'cv',
         });

my $id_counter = $max_id + 1;

while (my ($allele_id, $details) = each %alleles) {
  my $allele = $details->{obj};

  my $genotype = $chado->resultset('Sequence::Feature')->create(
    {
      uniquename => "$uniquename_prefix$id_counter",
      name => $name_prefix . ($allele->name() // $allele->uniquename()) .
        '[' . ($details->{description} || $details->{allele_type}) . ']',
      type_id => $genotype_term->cvterm_id(),
      organism_id => $allele->organism_id(),
    }
  );

  $chado->resultset('Sequence::FeatureRelationship')->create({
    subject_id => $allele->feature_id(),
    object_id => $genotype->feature_id(),
    type_id => $part_of->cvterm_id(),
  });

  $id_counter++;
}

$guard->commit unless $dry_run;
