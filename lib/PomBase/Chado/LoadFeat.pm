package PomBase::Chado::LoadFeat;

=head1 NAME

PomBase::Chado::LoadFeat - Code for loading a feature into Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::LoadFeat

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;

use Moose;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::FeatureDumper';
with 'PomBase::Role::Embl::SystematicID';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::CoordCalculator';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';

has organism => (is => 'ro',
                 required => 1,
                 isa => 'Bio::Chado::Schema::Organism::Organism',
                );
has gene_data => (is => 'ro', isa => 'HashRef',
                  init_arg => undef,
                  default => sub {
                    tie my %gene_data, 'Tie::Hash::Indexed';
                    return \%gene_data;
                  },
                );
has qual_load => (is => 'ro', isa => 'PomBase::Chado::QualifierLoad',
                  init_arg => undef,
                  lazy => 1,
                  builder => '_build_qual_load');
has verbose => (is => 'ro', isa => 'Bool');

method _build_qual_load
{
  my $chado = $self->chado();
  my $config = $self->config();
  my $verbose = $self->verbose();

  return PomBase::Chado::QualifierLoad->new(chado => $chado,
                                            verbose => $verbose,
                                            config => $config
                                          );
}

my %feature_loader_conf = (
  CDS => {
    save => 1,
    so_type => 'gene',
    transcript_so_type => 'mRNA',
  },
  misc_RNA => {
    save => 1,
    so_type => 'gene',
    transcript_so_type => 'ncRNA',
  },
  tRNA => {
    save => 1,
    so_type => 'gene',
    transcript_so_type => 'tRNA',
  },
  snoRNA => {
    save => 1,
    so_type => 'gene',
    transcript_so_type => 'snoRNA',
  },
  snRNA => {
    save => 1,
    so_type => 'gene',
    transcript_so_type => 'snRNA',
  },
  rRNA => {
    save => 1,
    so_type => 'gene',
    transcript_so_type => 'rRNA',
  },
  LTR => {
    so_type => 'long_terminal_repeat',
  },
  repeat_region => {
    so_type => 'repeat_region',
  },
  "5'UTR" => {
    so_type => 'five_prime_UTR',
    collected => 1,
  },
  "3'UTR" => {
    so_type => 'three_prime_UTR',
    collected => 1,
  },
  "exon" => {
    so_type => undef,
    collected => 1,
  },
  "intron" => {
    so_type => 'intron',
    collected => 1,
  },
  misc_feature => {
    so_type => 'region',
  },
  gap => {
    so_type => 'gap',
  },
  conflict => {
    so_type => 'sequence_conflict',
  },
  polyA_signal => {
    so_type => 'polyA_signal_sequence',
  },
  polyA_site => {
    so_type => 'polyA_site',
  },
  promoter => {
    so_type => 'promoter',
  },
  rep_origin => {
    so_type => 'origin_of_replication',
  },
);

method prepare_gene_data($uniquename)
{
  my $data;

  if (defined $self->gene_data()->{$uniquename}) {
    $data = $self->gene_data()->{$uniquename};
  } else {
    $data = {};
    $self->gene_data()->{$uniquename} = $data;
  }

  push @{$data->{"5'UTR_features"}}, ();
  push @{$data->{"3'UTR_features"}}, ();
  push @{$data->{"intron_features"}}, ();

  return $data;
}

method save_gene($feature, $uniquename)
{
  my $feat_type = $feature->primary_tag();
  my $so_type = $feature_loader_conf{$feat_type}->{so_type};

  if (!defined $uniquename) {
    warn "$feat_type feature has no uniquename\n";
    return;
  }

  my $data = $self->prepare_gene_data($uniquename);

  $data->{bioperl_feature} = $feature;
  $data->{so_type} = $so_type;
  $data->{transcript_so_type} =
    $feature_loader_conf{$feat_type}->{transcript_so_type};
}

method save_utr($feature, $uniquename)
{
  my $feat_type = $feature->primary_tag();
  my $so_type = $feature_loader_conf{$feat_type}->{so_type};

  my $data = $self->prepare_gene_data($uniquename);

  my %feature_data = (
    bioperl_feature => $feature,
    chado_feature => undef,
  );

  push @{$self->gene_data()->{$uniquename}->{"${feat_type}_features"}},
       {%feature_data};
}

method process($feature, $chromosome)
{
  my $feat_type = $feature->primary_tag();
  my $so_type = $feature_loader_conf{$feat_type}->{so_type};

  if (!defined $so_type) {
    print "no SO type for $feat_type - skipping";
    return;
  }

  my ($uniquename, $gene_uniquename, $has_systematic_id) =
    $self->get_uniquename($feature, $so_type);

  print "processing $feat_type $uniquename\n";

  if ($feature_loader_conf{$feat_type}->{save}) {
    if ($so_type =~ /UTR/) {
      $self->save_utr($feature, $gene_uniquename);
    } else {
      $self->save_gene($feature, $gene_uniquename);
    }
    return;
  }

  my $chado_feature =
    $self->store_feature_and_loc($feature, $chromosome, $so_type);

  if ($feature_loader_conf{$feat_type}->{collected}) {
    if (!$has_systematic_id) {
      print "  $uniquename has no uniquename - skipping\n";
      return;
    }

    my %feature_data = (
      bioperl_feature => $feature,
      chado_feature => $chado_feature,
    );

    push @{$self->gene_data()->{$gene_uniquename}->{"${feat_type}_features"}},
         {%feature_data};
  }

  $self->process_qualifiers($feature, $chado_feature);

  return $chado_feature;
}

method store_product($feature, $product)
{
  $self->store_featureprop($feature, 'product', $product);
}

method store_note($feature, $note)
{
  $self->store_featureprop($feature, 'comment', $note);
}

method store_ec_number($feature, $ec_number)
{
  $self->store_featureprop($feature, 'EC_number', $ec_number);
}

method process_qualifiers($bioperl_feature, $chado_object)
{
  my $type = $bioperl_feature->primary_tag();
  my $verbose = $self->verbose();

  my $uniquename = $chado_object->uniquename();

  if ($bioperl_feature->has_tag("controlled_curation")) {
    for my $value ($bioperl_feature->get_tag_values("controlled_curation")) {
      my %unused_quals =
      $self->qual_load()->process_one_cc($chado_object, $bioperl_feature, $value);
      $self->qual_load()->check_unused_quals($value, %unused_quals);
      warn "\n" if $verbose;
    }
  }

  if ($bioperl_feature->has_tag("GO")) {
    for my $value ($bioperl_feature->get_tag_values("GO")) {
      my %unused_quals =
      $self->qual_load()->process_one_go_qual($chado_object, $bioperl_feature, $value);
      $self->qual_load()->check_unused_quals($value, %unused_quals);
      warn "\n" if $verbose;
    }
  }

  if ($type eq 'CDS' or $type eq 'misc_RNA') {
    if ($bioperl_feature->has_tag("product")) {
      my @products = $bioperl_feature->get_tag_values("product");
      if (@products > 1) {
        warn "  $uniquename has more than one product\n";
      } else {
        if (length $products[0] == 0) {
          warn "  zero length product for $uniquename\n";
        } else {
          $self->store_product($chado_object, $products[0]);
        }
      }
    } else {
      warn "  no product for $uniquename\n";
    }
  }

  if ($bioperl_feature->has_tag("note")) {
    for my $note ($bioperl_feature->get_tag_values("note")) {
      $self->store_note($chado_object, $note);
    }
  }

  if ($bioperl_feature->has_tag("db_xref")) {
    for my $dbxref_value ($bioperl_feature->get_tag_values("db_xref")) {
      $self->add_feature_dbxref($chado_object, $dbxref_value);
    }
  }

  if ($bioperl_feature->has_tag("EC_number")) {
    if ($type eq 'CDS') {
      my @ec_numbers = $bioperl_feature->get_tag_values("EC_number");
      if (@ec_numbers > 1) {
        warn "$type $uniquename has more than one EC number\n";
      }
      $self->store_ec_number($chado_object, $ec_numbers[0]);
    } else {
      warn "$uniquename $type can't have a /EC_number qualifier"
    }
  }
}

method store_feature_parts($uniquename, $bioperl_feature, $chromosome, $so_type)
{
  my $chado = $self->chado();

  my @coords_list = $self->coords_of_feature($bioperl_feature);
  my @new_parts = ();

  for (my $i = 0; $i < @coords_list; $i++) {
    my ($start, $end) = @{$coords_list[$i]};
    my $prefix;
    if ($so_type =~ /exon$/) {
      $prefix = "$uniquename:exon:"
    } else {
      $prefix = "$uniquename:$so_type:"
    }
    my $part_uniquename = $prefix . ($i + 1);
    my $chado_sub_feature =
      $self->store_feature($part_uniquename, undef, [], $so_type);

    push @new_parts, $chado_sub_feature;

    my $strand = $bioperl_feature->location()->strand();

    $self->store_location($chado_sub_feature, $chromosome, $strand,
                          $start, $end);
  }

  return @new_parts;
}

method store_gene_parts($uniquename, $bioperl_cds, $chromosome,
                        $transcript_so_type,
                        $utrs_5_prime, $utrs_3_prime, $introns)
{
  my $chado = $self->chado();
  my $cds_location = $bioperl_cds->location();
  my $gene_start = $cds_location->start();
  my $gene_end = $cds_location->end();

  my @utrs_data = (@$utrs_5_prime, @$utrs_3_prime);

  for my $utr_data (@utrs_data) {
    my $featureloc = $utr_data->{chado_feature}->featureloc_features()->first();
    my $utr_start = $featureloc->fmin() + 1;
    my $utr_end = $featureloc->fmax();

    if ($utr_start < $gene_start) {
      $gene_start = $utr_start;
    }
    if ($utr_end > $gene_end) {
      $gene_end = $utr_end;
    }
  }

  my $exon_so_type;

  my $transcript_uniquename = "$uniquename.1";
  my $transcript_so_type;

  if ($bioperl_cds->has_tag('pseudo')) {
    $transcript_so_type = 'pseudogenic_transcript';
    $exon_so_type = 'pseudogenic_exon';
  } else {
    $exon_so_type = 'exon';
  }

  my $chado_transcript = $self->store_feature($transcript_uniquename, undef, [],
                                        $transcript_so_type);
  my $strand = $bioperl_cds->location()->strand();
  $self->store_location($chado_transcript, $chromosome, $strand,
                        $gene_start, $gene_end);

  my @exons = $self->store_feature_parts($transcript_uniquename, $bioperl_cds,
                                         $chromosome, $exon_so_type);

  for my $exon (@exons) {
    $self->store_feature_rel($exon, $chado_transcript, 'part_of');
  }

  for my $utr_data (@$utrs_5_prime) {
    my @chado_utrs = $self->store_feature_parts($uniquename,
                                                $utr_data->{bioperl_feature},
                                                $chromosome, "five_prime_UTR");
    for my $chado_utr (@chado_utrs) {
      $self->store_feature_rel($chado_utr, $chado_transcript, 'part_of');
    }
  }

  for my $utr_data (@$utrs_3_prime) {
    my @chado_utrs = $self->store_feature_parts($uniquename,
                                                $utr_data->{bioperl_feature},
                                                $chromosome, "three_prime_UTR");
    for my $chado_utr (@chado_utrs) {
      $self->store_feature_rel($chado_utr, $chado_transcript, 'part_of');
    }
  }

  for my $intron (@$introns) {
    $self->store_feature_rel($intron->{chado_feature}, $chado_transcript, 'part_of');
  }

  if ($transcript_so_type eq 'mRNA') {
    my $chado_peptide = $self->store_feature("$transcript_uniquename:pep", undef,
                                             [], 'polypeptide');

    $self->store_feature_rel($chado_peptide, $chado_transcript, 'derives_from');

    $self->store_location($chado_peptide, $chromosome, $strand,
                          $gene_start, $gene_end);

    $self->store_product($chado_peptide);
  } else {
    $self->store_product($chado_transcript);
  }

  return ($gene_start, $gene_end, $chado_transcript);
}


method finalise($chromosome)
{
  while (my ($uniquename, $feature_data) = each %{$self->gene_data()}) {
    my $bioperl_feature = $feature_data->{bioperl_feature};
    my $so_type = $feature_data->{so_type};
    my $transcript_so_type = $feature_data->{transcript_so_type};

    if (!defined $bioperl_feature) {
      die "no feature for $uniquename\n";
    }

    my ($gene_start, $gene_end, $chado_transcript) =
      $self->store_gene_parts($uniquename,
                              $bioperl_feature,
                              $chromosome,
                              $transcript_so_type,
                              $feature_data->{"5'UTR_features"},
                              $feature_data->{"3'UTR_features"},
                              $feature_data->{"intron_features"},
                             );

    my $chado_gene =
      $self->store_feature_and_loc($bioperl_feature, $chromosome, $so_type,
                                   $gene_start, $gene_end);

    $self->process_qualifiers($bioperl_feature, $chado_gene);

    $self->store_feature_rel($chado_transcript, $chado_gene, 'part_of');
  }
}
