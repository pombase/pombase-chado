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

use utf8;
use open ':std', ':encoding(UTF-8)';

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

my $pombe_data = $metadata_result->{"http://www.pombase.org"};

if (!$pombe_data) {
  die "no pombe data found\n";
}

my @failed_ids = ();

my $json_encoder = JSON->new()->utf8()->canonical(1);

for my $gocam_id (@{$pombe_data}) {
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

  map {
    if ($_->{key} eq 'title' &&
        $_->{value} =~ /\(Dmel\)/) {
      # temporary hack, see:
      #   https://github.com/geneontology/minerva/issues/503
      warn "Skipping Dmel model: ", $gocam_id, "\n";
      next;
    }
  } @{$decoded_model->{annotations} // []};

  open my $model_out, '>', "$model_directory/gomodel:$gocam_id.json"
    or die "can't open $model_directory/$gocam_id.json for writing: $?\n";

  print $model_out $json_encoder->encode($decoded_model);

  close $model_out or die;
}

open (my $gocam_tool_fh, '-|:encoding(UTF-8)', "/var/pomcur/bin/pombase-gocam-tool make-chado-data $model_directory/*.json")
  or die "couldn't open pipe to pombase-gocam-tool: $!";

my $chado_data_string = do {
  local $/ = undef;
  <$gocam_tool_fh>;
};

my $chado_data = decode_json $chado_data_string;

open my $gene_output_file, '>', $gene_mapping_filename or die;
open my $term_output_file, '>', $term_mapping_filename or die;

for my $gocam_id (sort keys %$chado_data) {
  my $model_details = $chado_data->{$gocam_id};

  if ($model_details->{title}) {
    # could have been done in pombase-gocam-tool, but much
    # easier in Perl
    $model_details->{title} =~ s/\n/ /g;
    $model_details->{title} =~ s/[\t ]+/ /g;
    $model_details->{title} =~ s/^\s+//;
    $model_details->{title} =~ s/\s+$//;
    $model_details->{title} =~ s/\(\s*(GO:\d\d\d\d+)\s*\)/($1)/g;
  }

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
print $go_cam_json_file $json_encoder->encode($chado_data), "\n";
close $go_cam_json_file;
