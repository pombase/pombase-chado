#!/usr/bin/env perl

# Read write Noctua GPAD and API to (re-)create the term and gene mapping files
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

my $request = HTTP::Request->new(GET => "http://snapshot.geneontology.org/products/upstream_and_raw_data/noctua_pombase.gpad.gz");
my $response = $ua->request($request);

my $gpad_contents = undef;

if ($response->is_success()) {
  my $gunzip = new Compress::Raw::Zlib::Inflate(WindowBits => WANT_GZIP);
  my $status = $gunzip->inflate($response->content(), $gpad_contents);
} else {
  die "can't download noctua_pombase.gpad.gz\n";
}

if (!$gpad_contents || length $gpad_contents == 0) {
  die "noctua_pombase.gpad.gz is empty\n";
}

my %all_details = ();

for my $gpad_line (split /\n/, $gpad_contents) {
  if ($gpad_line =~ /^!/) {
    if ($gpad_line eq '!gpa-version: 1.2') {
      next;
    } else {
      die "wrong GPAD version: $gpad_line";
    }
  }

  my ($db, $object_id, $qual, $go_term, $reference, $evidence, $with_from,
      $interacting_taxon_id, $date, $assigned_by, $extension, $properties) = split /\t/, $gpad_line;

  my @attrs = ();

  if ($properties) {
    @attrs = split /\|/, $properties;
  }

  my $gocam_id;

  map {
    if (/noctua-model-id=gomodel:(.*)/) {
      $gocam_id = $1;
    }
  } @attrs;

  if (!defined $gocam_id) {
    die "no noctua-model-id in properties: $gpad_line";
  }

  if (!grep { $_ eq $object_id } @{$all_details{$gocam_id}->{genes} // []}) {
    push @{$all_details{$gocam_id}->{genes}}, $object_id;
  }
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

sub get_process_terms
{
  my $model_details = shift;

  my @process_terms = ();

  for my $individual (@{$model_details->{individuals} // []}) {
    my $type_id = type_id_of_individual($individual);

    if (grep {
      $_->{id} eq 'GO:0008150'
    } @{$individual->{'root-type'} // []}) {
      if (!grep { $_ eq $type_id } @process_terms) {
        push @process_terms, $type_id;
      }
    }
  }

  return @process_terms;
}

my $term_count = 0;

for my $gocam_id (keys %all_details) {
  my $model_title;

  print "requesting details of $gocam_id from API\n";

  $request = HTTP::Request->new(GET => "https://api.geneontology.org/api/go-cam/$gocam_id");
  $request->header("accept" => "application/json");
$request->header("user-agent" => "evil");
  $response = $ua->request($request);

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

  my @process_terms = get_process_terms($api_model);

  $term_count += scalar(@process_terms);

  $all_details{$gocam_id}->{process_terms} = \@process_terms;
}

if ($term_count < 10) {
  die "internal error: missing many process terms - not writing\n";
}


if (scalar (keys %all_details) < 10) {
  die "internal error: missing many models - not writing\n";
}

open my $gene_output_file, '>', $gene_mapping_filename or die;
open my $term_output_file, '>', $term_mapping_filename or die;

for my $gocam_id (keys %all_details) {
  my $model_details = $all_details{$gocam_id};

  my $gocam = $gocam_id;

  if (defined $model_details->{title}) {
    $gocam .= ':' . $model_details->{title};
  }

  for my $gene (@{$model_details->{genes}}) {
    print $gene_output_file "$gene\t$gocam\n";
  }

  for my $process_term (@{$model_details->{process_terms} // []}) {
    print $term_output_file "$process_term\t$gocam\n";
  }
}

close $gene_output_file;
close $term_output_file;
