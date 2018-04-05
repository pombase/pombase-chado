#!/usr/bin/env perl

use warnings;
use strict;

use Text::CSV;
use JSON;
use Data::Dumper;

my $track_json_filename = shift;
my $track_metadata_csv = shift;
my $output_track_json_filename = shift;
my $output_track_metadata_csv = shift;

open my $track_json_fh, '<', $track_json_filename or die;

my $track_json_text = '';

{
  local $/ = undef;

  $track_json_text = <$track_json_fh>;
}

my $track_json = decode_json($track_json_text);

my $csv = Text::CSV->new ();
$csv->eol ("\n");

my @new_tracks = ();

open my $fh, "<", $track_metadata_csv;
$csv->header ($fh);

my @column_names_to_filter =
  qw(display_in_jbrowse ensembl_source_name short_description data_file_type);

my @output_column_names =
  grep {
    my $column_name = $_;
    !grep { $_ eq $column_name } @column_names_to_filter;
  } $csv->column_names();

open my $out_csv_fh, '>', $output_track_metadata_csv or die;

$csv->print($out_csv_fh, \@output_column_names);

while (my $row = $csv->getline_hr ($fh)) {
  next unless $row->{display_in_jbrowse} =~ /^y/i;

  my $store_class = undef;

  if (lc $row->{data_file_type} eq 'bigwig') {
    $store_class = "JBrowse/Store/SeqFeature/BigWig";
  } else {
    if (lc $row->{data_file_type} eq 'rnaseq') {
      $store_class = "JBrowse/Store/SeqFeature/BAM";
    } else {
      if (lc $row->{data_file_type} eq 'bed') {
        warn "skipping BED file config - not handled yet: ", Dumper([$row]);
        next;
      }
    }
  }

  if ($store_class) {
    my $new_track = {
      key => $row->{label},
      label => $row->{label},
      urlTemplate => $row->{source_url},
      type => $row->{data_file_type} eq 'bigWig' ? "JBrowse/View/Track/Wiggle/XYPlot" : "Alignments2",
      storeClass => $store_class,
      autoscale => 'local',
    };

    if ($row->{strand}) {
      if ($row->{strand} eq 'forward') {
        $new_track->{style} = {
          pos_color => '#B00',
        };
      } else {
        $new_track->{style} = {
          pos_color => '#00B',
        };
      }
    }

    push @new_tracks, $new_track;
  } else {
    die 'unknown storage class for: ', Dumper([$row]);
  }

  my @out_row = map {
    $row->{$_};
  } @output_column_names;

  $csv->print($out_csv_fh, \@out_row);
}

push @{$track_json->{tracks}}, sort { $a->{key} cmp $b->{key} } @new_tracks;

my $json = JSON->new()->allow_nonref();

open my $out_json_fh, '>', $output_track_json_filename or die;

print $out_json_fh $json->pretty()->encode($track_json);
