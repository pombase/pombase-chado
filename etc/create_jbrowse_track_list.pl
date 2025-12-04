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
my $jbrowse2_config_filename = shift;

my $assembly_name = "pombe_v1";

open my $track_json_fh, '<', $track_json_filename or die;

my $track_json_text = '';

{
  local $/ = undef;

  $track_json_text = <$track_json_fh>;
}

my @small_track_list_json = ();

my $internal_datasets_url = "https://www.pombase.org/internal_datasets";
my $chromosome_fasta_url = "$internal_datasets_url/bgzip_chromosomes/Schizosaccharomyces_pombe_all_chromosomes.fa.gz";

my %feature_format_details = (
  feature => "jexl:{ gene_page: '<a href=\"/gene/'+feature.id+'\">'+(feature.name || feature.id)+'</a>',  id: '<a href=\"/gene/'+feature.id+'\">'+feature.id+'</a>'}"
);

my %jbrowse2_config = (
  assemblies => [
    {
      name => $assembly_name,
      sequence => {
        type => "ReferenceSequenceTrack",
        trackId => "pombe_v1-ReferenceSequenceTrack",
        adapter => {
          type => "BgzipFastaAdapter",
          fastaLocation => {
            uri => $chromosome_fasta_url,
            locationType => "UriLocation"
          },
          faiLocation => {
            uri => "$chromosome_fasta_url.fai",
            locationType => "UriLocation"
          },
          gziLocation => {
            uri => "$chromosome_fasta_url.gzi",
            locationType => "UriLocation"
          }
        }
      }
    }
  ],
  plugins => [
    {
      name => "PomBasePlugin",
      umdLoc => { uri => "PomBasePlugin.js" }
    },
    {
      name => "Protein3d",
      url => "https://jbrowse.org/plugins/jbrowse-plugin-protein3d/dist/jbrowse-plugin-protein3d.umd.production.min.js"
    },
    {
      name => "MsaView",
      url => "https://jbrowse.org/plugins/jbrowse-plugin-msaview/dist/jbrowse-plugin-msaview.umd.production.min.js"
    },
  ],
  configuration => {},
  connections => [],
  defaultSession => {
    "drawerPosition" => "right",
    "drawerWidth" => 384,
    "widgets" => {
      "GridBookmark" => {
        "id" => "GridBookmark",
        "type" => "GridBookmarkWidget"
      },
      "hierarchicalTrackSelector" => {
        "id" => "hierarchicalTrackSelector",
        "type" => "HierarchicalTrackSelectorWidget",
        "view" => "aY9idd8f2C2kSUvXuKVup",
        "faceted" => {
          "filterText" => "",
          "showSparse" => $JSON::false,
          "showFilters" => $JSON::true,
          "showOptions" => $JSON::false,
          "panelWidth" => 400
        }
      }
    },
    "activeWidgets" => {
      "hierarchicalTrackSelector" => "hierarchicalTrackSelector"
    },
    "minimized" => $JSON::false,
    "id" => "JWpCwnCeYbRXMEjEe5pU7",
    "name" => "New Session 5/28/2025, 8:10:23 PM",
    "margin" => 0,
    "views" => [
      {
        "id" => "aY9idd8f2C2kSUvXuKVup",
        "minimized" => $JSON::false,
        "type" => "LinearGenomeView",
        "offsetPx" => 52,
        "bpPerPx" => 93.86789039167218,
        "displayedRegions" => [
          {
            "reversed" => $JSON::false,
            "refName" => "I",
            "start" => 0,
            "end" => 5579133,
            "assemblyName" => "pombe_v1"
          }
        ],
        "tracks" => [
          {
            "id" => "xMs68Mq59h7_nLGenDzwh",
            "type" => "ReferenceSequenceTrack",
            "configuration" => "pombe_v1-ReferenceSequenceTrack",
            "minimized" => $JSON::false,
            "pinned" => $JSON::false,
            "displays" => [
              {
                "id" => "782oEcUAfTCYkfDWJvlsr",
                "type" => "LinearReferenceSequenceDisplay",
                "heightPreConfig" => 50,
                "configuration" => "pombe_v1-ReferenceSequenceTrack-LinearReferenceSequenceDisplay",
                "showForward" => $JSON::true,
                "showReverse" => $JSON::true,
                "showTranslation" => $JSON::true
              }
            ]
          },
          {
            "id" => "W6JWqFYv06JSil2RogXwn",
            "type" => "FeatureTrack",
            "configuration" => "Schizosaccharomyces_pombe_all_chromosomes_forward_strand",
            "minimized" => $JSON::false,
            "pinned" => $JSON::false,
            "displays" => [
              {
                "id" => "MuOc9eKVHC7EMUoOMdJ3W",
                "type" => "LinearBasicDisplay",
                "heightPreConfig" => 224,
                "configuration" => "Schizosaccharomyces_pombe_all_chromosomes_forward_strand-LinearBasicDisplay"
              }
            ]
          },
          {
            "id" => "2e7HCYG0ZE2Bx7rSASPv9",
            "type" => "FeatureTrack",
            "configuration" => "Schizosaccharomyces_pombe_all_chromosomes_reverse_strand",
            "minimized" => $JSON::false,
            "pinned" => $JSON::false,
            "displays" => [
              {
                "id" => "KIl1sI_k-47WCVHEgw7eU",
                "type" => "LinearBasicDisplay",
                "heightPreConfig" => 237,
                "configuration" => "Schizosaccharomyces_pombe_all_chromosomes_reverse_strand-LinearBasicDisplay"
              }
            ]
          }
        ],
        "hideHeader" => $JSON::false,
        "hideHeaderOverview" => $JSON::false,
        "hideNoTracksActive" => $JSON::false,
        "trackSelectorType" => "hierarchical",
        "showCenterLine" => $JSON::false,
        "showCytobandsSetting" => $JSON::true,
        "trackLabels" => "",
        "showGridlines" => $JSON::true,
        "highlight" => [],
        "colorByCDS" => $JSON::false,
        "showTrackOutlines" => $JSON::true,
        "bookmarkHighlightsVisible" => $JSON::true,
        "bookmarkLabelsVisible" => $JSON::true
      }
    ],
    "stickyViewHeaders" => $JSON::true,
    "sessionTracks" => [],
    "sessionAssemblies" => [],
    "temporaryAssemblies" => [],
    "connectionInstances" => [],
    "sessionConnections" => [],
    "focusedViewId" => "aY9idd8f2C2kSUvXuKVup",
    "sessionPlugins" => []
  },
  aggregateTextSearchAdapters => [
    {
      type => "TrixTextSearchAdapter",
      textSearchAdapterId => "pombe_v1-index",
      ixFilePath => {
        uri => "$internal_datasets_url/jbrowse2_trix/pombe_v1.ix",
        locationType => "UriLocation"
      },
      ixxFilePath => {
        uri => "$internal_datasets_url/jbrowse2_trix/pombe_v1.ixx",
        locationType => "UriLocation"
      },
      metaFilePath => {
        uri => "$internal_datasets_url/jbrowse2_trix/pombe_v1_meta.json",
        locationType => "UriLocation"
      },
      assemblyNames => [
        "pombe_v1"
      ]
    }
  ],
  tracks => [
    {
      type => "FeatureTrack",
      trackId => "Schizosaccharomyces_pombe_all_chromosomes_forward_strand",
      name => "Forward strand",
      adapter => {
        type => "Gff3Adapter",
        gffLocation => {
          uri => "Schizosaccharomyces_pombe_all_chromosomes_forward_strand.gff3",
          locationType => "UriLocation"
        }
      },
      formatDetails => \%feature_format_details,
      category => [
        "Genes"
      ],
      assemblyNames => [
        $assembly_name,
      ],
      displays => [
        {
          type => "LinearBasicDisplay",
          displayId => "Schizosaccharomyces_pombe_all_chromosomes_forward_strand-LinearBasicDisplay",
          renderer => {
            type => "SvgFeatureRenderer",
            color1 => "jexl:featureColor(feature)",
            height => "jexl:featureHeight(feature)",
            labels => {
              fontSize => "jexl:featureLabelFontSize(feature)",
            },
          }
        },
      ]
    },
    {
      type => "FeatureTrack",
      trackId => "Schizosaccharomyces_pombe_all_chromosomes_reverse_strand",
      name => "Reverse strand",
      adapter => {
        type => "Gff3Adapter",
        gffLocation => {
          uri => "Schizosaccharomyces_pombe_all_chromosomes_reverse_strand.gff3",
          locationType => "UriLocation"
        }
      },
      formatDetails => \%feature_format_details,
      category => [
        "Genes"
      ],
      assemblyNames => [
        $assembly_name,
      ],
      displays => [
        {
          type => "LinearBasicDisplay",
          displayId => "Schizosaccharomyces_pombe_all_chromosomes_reverse_strand-LinearBasicDisplay",
          renderer => {
            type => "SvgFeatureRenderer",
            color1 => "jexl:featureColor(feature)",
            height => "jexl:featureHeight(feature)",
            labels => {
              fontSize => "jexl:featureLabelFontSize(feature)",
            },
          }
        },
      ],
    },
  ],
);

sub maybe_add_jbrowse2_track
{
  my $track_id = shift;
  my $row = shift;

  return unless defined $jbrowse2_config_filename;

  my %track_conf = (
    name => $row->{label},
    trackId => $track_id,
    category => [
      $row->{data_type},
    ],
    assemblyNames => [
      $assembly_name
    ],
    metadata => {
      pmid => $row->{pmed_id},
      first_author => $row->{first_author},
      study_id => $row->{study_id},
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
    }
  );

  if (lc $row->{data_file_type} eq 'bigwig') {
    $track_conf{type} = 'QuantitativeTrack';
    $track_conf{adapter} = {
      type => "BigWigAdapter",
      bigWigLocation => {
        uri => $row->{source_url},
        locationType => "UriLocation"
      }
    };
    push @{$jbrowse2_config{tracks}}, \%track_conf;
    return;
  }

  if (lc $row->{data_file_type} eq 'gff') {
    $track_conf{type} = 'FeatureTrack';
    $track_conf{adapter} = {
      type => "Gff3TabixAdapter",
      gffGzLocation => {
        uri => $row->{source_url},
        locationType => "UriLocation"
      },
      index => {
        location => {
          uri => $row->{source_url} . ".tbi",
          locationType => "UriLocation"
        },
        indexType => "TBI"
      }
    };
    push @{$jbrowse2_config{tracks}}, \%track_conf;
    return;
  }

  if (lc $row->{data_file_type} eq 'rnaseq') {
    $track_conf{type} = "AlignmentsTrack";
    $track_conf{adapter} = {
      type => "BamAdapter",
      bamLocation => {
        uri => $row->{source_url},
        locationType => "UriLocation"
      },
      index => {
        location => {
          uri => $row->{source_url} . ".bai",
          locationType => "UriLocation"
        },
        indexType => "BAI"
      },
      sequenceAdapter => {
        type => "BgzipFastaAdapter",
        fastaLocation => {
          uri => $chromosome_fasta_url,
          locationType => "UriLocation"
        },
        faiLocation => {
          uri => "$chromosome_fasta_url.fai",
          locationType => "UriLocation"
        },
        gziLocation => {
          uri => "$chromosome_fasta_url.gzi",
          locationType => "UriLocation"
        },
      }
    };
    push @{$jbrowse2_config{tracks}}, \%track_conf;
    return;
  }

 if (lc $row->{data_file_type} eq 'vcf') {
    $track_conf{type} = "VariantTrack";
    $track_conf{adapter} = {
      type => "VcfTabixAdapter",
      vcfGzLocation => {
        uri => $row->{source_url},
        locationType => "UriLocation"
      },
      index => {
        location => {
          uri => $row->{source_url} . ".tbi",
          locationType => "UriLocation"
        },
        indexType => "TBI"
      }
    };
    push @{$jbrowse2_config{tracks}}, \%track_conf;
    return;
  }

  if (lc $row->{data_file_type} eq 'bed') {
    $track_conf{type} = 'FeatureTrack';
    $track_conf{adapter} = {
      type => "BedTabixAdapter",
      bedGzLocation => {
        uri => $row->{source_url},
        locationType => "UriLocation"
      },
      index => {
        location => {
          uri => $row->{source_url} . ".tbi",
          locationType => "UriLocation"
        },
        indexType => "TBI"
      }
    };
    push @{$jbrowse2_config{tracks}}, \%track_conf;
    return;
  }
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

  my $show_feature_label = $row->{show_feature_label};

  my @out_row = map {
    $row->{$_};
  } @output_column_names;

  $csv->print($out_csv_fh, \@out_row);

  next if $row->{label} =~ /(Forward|Reverse) strand features|DNA sequence/;

  my $track_id =
    ($row->{source_url} =~ s|.*/(.*?)\.\w+$|$1|r);

  if ($row->{pmed_id}) {
    $track_id = $row->{pmed_id} . '-' . $track_id;
  }

  maybe_add_jbrowse2_track($track_id, $row, $assembly_name);

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
        track_id => $track_id,
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

if (defined $jbrowse2_config_filename) {
  open my $jbrowse2_config_fh, '>', $jbrowse2_config_filename
    or die "can't write $jbrowse2_config_filename";

  print $jbrowse2_config_fh $json->encode(\%jbrowse2_config);

  close $jbrowse2_config_fh;
}
