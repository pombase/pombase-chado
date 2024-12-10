#!/usr/bin/env perl

# Parse the pombe data file from the Complex Portal FTP site
# http://ftp.ebi.ac.uk/pub/databases/intact/complex/current/complextab/284812.tsv
# and write a file of pombe ID to Complex Portal ID mappings
# and a file of Complex Portal IDs and complex names

use strict;
use warnings;
use Carp;

if (@ARGV != 5) {
  die qq|$0: needs 5 arguments:
Input:
 - PomBase2UniProt.tsv  (pombe-embl/ftp_site/pombe/names_and_identifiers/)
 - complex_portal_pombe_data.tsv  (from http://ftp.ebi.ac.uk/pub/databases/intact/complex/current/complextab/284812.tsv)
 - Complex_Portal_PubMed_ID  (probably "PMID:30357405")
Output:
 - pombe_to_complex_id_mapping.tsv
 - complex_id_and_names.tsv
|;
}


my $uniprot_mapping_filename = shift;

open my $uniprot_mapping, '<', $uniprot_mapping_filename
  or die "can't open $uniprot_mapping_filename: $?";

my %uniprot_map = ();

while (defined (my $line = <$uniprot_mapping>)) {
  next if $line =~ /^#/;

  chomp $line;

  my ($pombe_id, $uniprot_id) = split /\t/, $line;

  $uniprot_map{$uniprot_id} = $pombe_id;
}

close $uniprot_mapping;


my $complex_portal_filename = shift;

open my $complex_portal_file, '<', $complex_portal_filename
  or die "can't open $complex_portal_filename: $?";

my $complex_portal_pubmed_id = shift;

my $pombe_to_complex_id_mapping_filename = shift;

open my $pombe_to_complex_id_mapping_file, '>', $pombe_to_complex_id_mapping_filename
  or die "can't open $pombe_to_complex_id_mapping_filename: $?";

my $complex_ids_and_names_filename = shift;

open my $complex_ids_and_names_file, '>', $complex_ids_and_names_filename
  or die "can't open $complex_ids_and_names_filename: $?";


while (defined (my $line = <$complex_portal_file>)) {
  next if $line =~ /^#/;

  chomp $line;

  my ($complex_portal_acc, $complex_name, $aliases, $taxon, $identifers, $evidence) =
    split /\t/, $line;

  print $complex_ids_and_names_file "$complex_portal_acc\t$complex_name\n";

  for my $id_details (split /\|/, $identifers) {
    if ($id_details =~ /(.*)\(.*\)/) {
      if ($id_details !~ /CHEBI:\d+/) {
        my $pombe_id = $uniprot_map{$1};

        if (defined $pombe_id) {
          print $pombe_to_complex_id_mapping_file "$pombe_id\t$complex_portal_acc\t$complex_portal_pubmed_id\n";
        } else {
          warn "$complex_portal_filename:$.: can't find pombe ID for $1\n";
        }
      }
    } else {
      die "$complex_portal_filename:$.: can't parse ID details: $id_details\n";
    }
  }
}

close $complex_portal_file or die;
close $pombe_to_complex_id_mapping_file or die;
close $complex_ids_and_names_file or die;
