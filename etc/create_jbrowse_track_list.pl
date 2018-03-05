#!/usr/bin/env perl

use warnings;
use strict;

use Text::CSV;
use JSON;

my $track_json_filename = shift;
open my $track_json_fh, '<', $track_json_filename or die;

my $track_json_text = '';

{
  local $/ = undef;

  $track_json_text = <$track_json_fh>;
}

my $track_json = decode_json($track_json_text);

my $track_metadata_csv = shift;

my $csv = Text::CSV->new ();

my @new_tracks = ();

open my $fh, "<", $track_metadata_csv;
$csv->header ($fh);
while (my $row = $csv->getline_hr ($fh)) {
  next unless $row->{display_in_jbrowse} =~ /^y/i;

  my $store_class = undef;

  if (lc $row->{data_file_type} eq 'bigwig') {
    $store_class = "JBrowse/Store/SeqFeature/BigWig";
  } else {
    if (lc $row->{data_file_type} eq 'rnaseq') {
      $store_class = "JBrowse/Store/SeqFeature/BAM";
    }
  }

  if ($store_class) {
    push @new_tracks, {
      key => $row->{label},
      label => $row->{label},
      urlTemplate => $row->{source_url},
      type => $row->{data_file_type} eq 'bigWig' ? "JBrowse/View/Track/Wiggle/XYPlot" : "Alignments2",
      storeClass => $store_class,
      autoscale => 'local',
    };
  } else {
    use Data::Dumper;
    die 'unknown storage class for: ', Dumper([$row]);
  }
}

push @{$track_json->{tracks}}, sort { $a->{key} cmp $b->{key} } @new_tracks;

my $json = JSON->new()->allow_nonref();

print $json->pretty()->encode($track_json);
