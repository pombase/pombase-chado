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
my $go_cam_json_filename = shift;
my $model_directory = shift;

my $ua = LWP::UserAgent->new(keep_alive => 1);

my $request = HTTP::Request->new(GET => "https://live-go-cam.geneontology.io/product/json/provider-to-model.json");
$request->header("user-agent" => "Evil");
$request->header("Accept" => "application/json");

my $response = $ua->request($request);

my $contents = undef;

if ($response->is_success()) {
  $contents = $response->content();
} else {
  die "can't download metadata: ",
    $response->status_line(), "\n";
}

if (!$contents || length $contents == 0) {
  die "no contents\n";
}

my $metadata_result = decode_json $contents;

my %all_details = ();

my $pombe_data = $metadata_result->{"http://www.pombase.org"};

if (!$pombe_data) {
  die "no pombe data found\n";
}

for my $id (@{$pombe_data}) {
  $all_details{$id} = {};
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
  my $model_title = shift;

  my %process_terms = ();
  my %title_terms = ();
  my %genes = ();
  my %modified_gene_pro_terms = ();

  for my $individual (@{$model_details->{individuals} // []}) {
    my $type_id = type_id_of_individual($individual);

    if ($type_id =~ /^(PR:\d\d\d\d\d+)$/) {
      $modified_gene_pro_terms{$1} = 1;
    }

    if ($type_id =~ /^PomBase:(.*)$/) {
      $genes{$1} = 1;
    }

    if (grep {
      $_->{id} eq 'GO:0008150'
    } @{$individual->{'root-type'} // []}) {
      $process_terms{$type_id} = 1;
    }
  }

  if ($model_title) {
    for my $go_termid ($model_title =~ /\(\s*(GO:\d+)\s*\)/g) {
      $process_terms{$go_termid} = 1;
      $title_terms{$go_termid} = 1;
    }
  }

  return ([sort keys %title_terms], [sort keys %process_terms],
          [sort keys %genes], [sort keys %modified_gene_pro_terms]);
}

my $term_count = 0;

my @failed_ids = ();

my $json_encoder = JSON->new()->utf8()->canonical(1);

for my $gocam_id (keys %all_details) {
  print "requesting details of $gocam_id from API\n";

  $request = HTTP::Request->new(GET => "https://live-go-cam.geneontology.io/product/json/low-level/$gocam_id.json");
  $request->header("accept" => "application/json");
  $request->header("user-agent" => "Evil");
  $response = $ua->request($request);

  if (!$response->is_success()) {
    print "  request failed: ", $response->status_line(), " - skipping\n";
    push @failed_ids, $gocam_id;
    next;
  }

  my $content = $response->content();
  my $decoded_model = decode_json $content;

  my %model_annotations = ();

  map {
    push @{$model_annotations{$_->{key}}}, $_->{value};
  } @{$decoded_model->{annotations} // []};

  my $model_title = undef;

  if (exists $model_annotations{title}) {
    $model_title = $model_annotations{title}->[0];
  }

  if (exists $model_annotations{date}) {
    my $model_date = $model_annotations{date}->[0];
    $all_details{$gocam_id}->{date} = $model_date;
  }

  my @contributors = ();

  if (exists $model_annotations{contributor}) {
    @contributors = map {
      s|.*orcid.org/||;
      $_
    } @{$model_annotations{contributor}};
  }

  if ($model_title) {
    $model_title =~ s/\n/ /g;
    $model_title =~ s/[\t ]+/ /g;
    $model_title =~ s/^\s+//;
    $model_title =~ s/\s+$//;
    $all_details{$gocam_id}->{title} = $model_title;
  }

  my ($title_terms, $process_terms, $genes, $modified_gene_pro_terms) =
    get_process_terms_and_genes($decoded_model, $model_title);

  if (!@$genes) {
    print "$gocam_id has no pombe genes, skipping\n";
    push @failed_ids, $gocam_id;
    next;
  }

  $term_count += scalar(@$process_terms);

  $all_details{$gocam_id}->{title_terms} = $title_terms;
  $all_details{$gocam_id}->{process_terms} = $process_terms;
  $all_details{$gocam_id}->{genes} = $genes;
  $all_details{$gocam_id}->{modified_gene_pro_terms} = $modified_gene_pro_terms;
  $all_details{$gocam_id}->{contributors} = [sort @contributors];

  open my $model_out, '>', "$model_directory/gomodel:$gocam_id.json"
    or die "can't open $model_directory/$gocam_id.json for writing: $?\n";

  print $model_out $json_encoder->encode($decoded_model);

  close $model_out or die;
}

for my $gocam_id (@failed_ids) {
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

open my $go_cam_json_file, '>', $go_cam_json_filename or die;
print $go_cam_json_file $json_encoder->encode(\%all_details), "\n";
close $go_cam_json_file;
