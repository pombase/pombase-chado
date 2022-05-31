#!/usr/bin/env perl

use warnings;
use strict;

use Text::CSV;
use JSON;
use Data::Dumper;

use autodie;
use open ':encoding(UTF-8)';

my $track_json_filename = shift;
my $track_metadata_csv = shift;
my $output_track_json_filename = shift;
my $output_track_metadata_csv = shift;
my $small_track_list_json_filename = shift;

open my $track_json_fh, '<', $track_json_filename or die;

my $track_json_text = '';

{
  local $/ = undef;

  $track_json_text = <$track_json_fh>;
}

my @small_track_list_json = ();

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

  my $show_feature_label = $row->{show_feature_label};

  my @out_row = map {
    $row->{$_};
  } @output_column_names;

  $csv->print($out_csv_fh, \@out_row);

  next if $row->{label} =~ /(Forward|Reverse) strand features|DNA sequence/;

  my $store_class = undef;

  if (lc $row->{data_file_type} eq 'bigwig') {
    $store_class = "JBrowse/Store/SeqFeature/BigWig";
  } else {
    if (lc $row->{data_file_type} eq 'rnaseq') {
      $store_class = "JBrowse/Store/SeqFeature/BAM";
    } else {
      if (lc $row->{data_file_type} eq 'bed') {
        $store_class = "JBrowse/Store/SeqFeature/BEDTabix"
      } else {
        if (lc $row->{data_file_type} eq 'vcf') {
          $store_class = "JBrowse/Store/SeqFeature/VCFTabix"
        } else {
          if (lc $row->{data_file_type} =~ /^gff[23]?$/i) {
            $store_class = "JBrowse/Store/SeqFeature/GFF3Tabix";
          } else {
            warn "skipping file config - not handled yet: ", Dumper([$row]);
            next;
          }
        }
      }
    }
  }

  if ($store_class) {
    my $track_type;

    my %style = ();

    if ($row->{strand}) {
      if ($row->{strand} =~ /forward/) {
        $style{pos_color} = '#00B';
      } else {
        $style{pos_color} = '#B00',
      }
    }

    if ($row->{data_file_type} eq 'bigWig') {
      $track_type = "JBrowse/View/Track/Wiggle/XYPlot";
    } else {
      if ($row->{data_file_type} eq 'bed') {
        $track_type = "JBrowse/View/Track/HTMLFeatures";
        $style{featureCss} = "background-color: #666; height: 1.5em; border: 2px solid #666;";

        # enable arrows for now, see:
        # https://github.com/pombase/website/issues/792#issuecomment-393875208
        # $style{arrowheadClass} = undef;
      } else {
        if ($row->{data_file_type} eq 'vcf') {
          $track_type = 'CanvasVariants';
        } else {
          if ($row->{data_file_type} =~ /^gff[23]?/i) {
            $track_type = 'CanvasFeatures';
          } else {
            $track_type = "Alignments2";
          }
        }
      }
    }

    if ($show_feature_label =~ /^n/i) {
      $style{label} = "_NOLABEL_";
    }

    my $pmed_id = $row->{pmed_id};

    if ($pmed_id) {
      push @small_track_list_json, {
        pmed_id => $pmed_id,
        label => $row->{label},
        growth_phase_or_response => $row->{growth_phase_or_response},
        assayed_gene_product => $row->{assayed_gene_product},
        background => $row->{background},
        conditions => $row->{conditions},
        assay_type => $row->{assay_type},
        data_type => $row->{data_type},
        alleles => $row->{alleles},
        mutants => $row->{'mutant(s)'},
        comment => $row->{comment},
        source_url => $row->{source_url},
      };
    }

    my $new_track = {
      key => $row->{label},
      label => $row->{label},
      urlTemplate => $row->{source_url},
      type => $track_type,
      storeClass => $store_class,
      autoscale => 'local',
    };

    if ($track_type eq 'Alignments2') {
      my $url = $row->{source_url};
      $url =~ s/\.bam$/.bw/;
      $new_track->{histograms}->{urlTemplate} = $url;
    }

    if (scalar keys %style > 0) {
      $new_track->{style} = \%style;
    }

    push @new_tracks, $new_track;
  } else {
    die 'unknown storage class for: ', Dumper([$row]);
  }
}

push @{$track_json->{tracks}}, sort { $a->{key} cmp $b->{key} } @new_tracks;

my $json = JSON->new()->allow_nonref();

open my $out_json_fh, '>', $output_track_json_filename or die;

print $out_json_fh $json->encode($track_json);

close $out_json_fh;

open my $out_small_json_fh, '>', $small_track_list_json_filename
  or die "can't write $small_track_list_json_filename";

print $out_small_json_fh $json->encode(\@small_track_list_json);

close $out_small_json_fh;

