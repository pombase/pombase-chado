#!/usr/bin/env perl

# Read Noctua GPAD and API to (re-)create the term and gene mapping files
# Run as:
#   ./etc/generate_gocam_data_files.pl pombe-embl/supporting_files/production_gocam_id_mapping.tsv pombe-embl/supporting_files/production_gocam_term_id_mapping.tsv
# then svn commit the files

use strict;
use warnings;
use LWP::UserAgent;
use Compress::Zlib;
use Data::Dumper;
use JSON qw|decode_json encode_json|;

my $gene_mapping_filename = shift;
my $term_mapping_filename = shift;

my $ua = LWP::UserAgent->new();

my $request = HTTP::Request->new(GET => "http://barista.berkeleybop.org/search//models?offset=0&limit=50&group=http://www.pombase.org&state=production&expand&debug");
$request->header("user-agent" => "Evil");
$request->header("Accept" => "application/json");

my $response = $ua->request($request);

my $contents = undef;

if ($response->is_success()) {
  $contents = $response->content();
} else {
  die "can't download from Noctua: ",
    $response->status_line(), "\n";
}

if (!$contents || length $contents == 0) {
  die "no contents\n";
}

my $noctua_result = decode_json $contents;;

my %all_details = ();

for my $model_detail (@{$noctua_result->{models}}) {
  $all_details{$model_detail->{id} =~ s/gomodel:(.*)/$1/r} = {};
}

sub type_id_of_individual
{
  my $individual = shift;

  my $type_id;

  map {
    if ($_->{type} eq 'class') {
      $type_id = $_->{id};
    }
  } @{$individual->{type} // []};

  return $type_id;
}

sub get_process_terms_and_genes
{
  my $model_details = shift;

  my %process_terms = ();
  my %genes = ();

  for my $individual (@{$model_details->{individuals} // []}) {
    my $type_id = type_id_of_individual($individual);

    if ($type_id =~ /^PomBase:(.*)$/) {
      $genes{$1} = 1;
    }

    if (grep {
      $_->{id} eq 'GO:0008150'
    } @{$individual->{'root-type'} // []}) {
      $process_terms{$type_id} = 1;
    }
  }

  return ([keys %process_terms], [keys %genes]);
}

my $term_count = 0;

my @api_failed_ids = ();

for my $gocam_id (keys %all_details) {
  my $model_title;

  print "requesting details of $gocam_id from API\n";

  $request = HTTP::Request->new(GET => "https://api.geneontology.xyz/gocam/gomodel:$gocam_id/raw");
  $request->header("accept" => "application/json");
  $request->header("user-agent" => "evil");
  $response = $ua->request($request);

  if (!$response->is_success()) {
    print "  request failed: ", $response->status_line(), " - skipping\n";
    push @api_failed_ids, $gocam_id;
    next;
  }

  my $api_model = decode_json $response->content();

  map {
    if ($_->{key} && $_->{key} eq 'title') {
      $model_title = $_->{value};
    }
  } @{$api_model->{annotations} // []};

  if ($model_title) {
    $model_title =~ s/\n/ /g;
    $model_title =~ s/[\t ]+/ /g;
    $all_details{$gocam_id}->{title} = $model_title;
  }

  my ($process_terms, $genes) = get_process_terms_and_genes($api_model);

  $term_count += scalar(@$process_terms);

  $all_details{$gocam_id}->{process_terms} = $process_terms;
  $all_details{$gocam_id}->{genes} = $genes;
}

for my $gocam_id (@api_failed_ids) {
  delete $all_details{$gocam_id};
}

if ($term_count < 10) {
  die "internal error: missing many process terms - not writing\n";
}


if (scalar (keys %all_details) < 10) {
  die "internal error: missing many models - not writing\n";
}

open my $gene_output_file, '>', $gene_mapping_filename or die;
open my $term_output_file, '>', $term_mapping_filename or die;

for my $gocam_id (sort keys %all_details) {
  my $model_details = $all_details{$gocam_id};

  my $gocam = $gocam_id;

  if (defined $model_details->{title}) {
    $gocam .= ':' . $model_details->{title};
  }

  for my $gene (sort @{$model_details->{genes}}) {
    print $gene_output_file "$gene\t$gocam\n";
  }

  for my $process_term (sort @{$model_details->{process_terms} // []}) {
    print $term_output_file "$process_term\t$gocam\n";
  }
}

close $gene_output_file;
close $term_output_file;
