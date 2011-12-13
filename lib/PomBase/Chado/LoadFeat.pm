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
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::FeatureDumper';
with 'PomBase::Role::Embl::SystematicID';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::CoordCalculator';
with 'PomBase::Role::QualifierSplitter';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';

has organism => (is => 'ro',
                 required => 1,
                );
has transcript_data => (is => 'ro', isa => 'HashRef',
                  init_arg => undef,
                  default => sub {
                    tie my %transcript_data, 'Tie::Hash::Indexed';
                    return \%transcript_data;
                  },
                );
has qual_load => (is => 'ro', isa => 'PomBase::Chado::QualifierLoad',
                  init_arg => undef,
                  lazy => 1,
                  builder => '_build_qual_load');
has verbose => (is => 'ro', isa => 'Bool');

has gene_objects => (is => 'ro', init_arg => undef, isa => 'HashRef',
                     default => sub { {} });

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
    transcript => 1,
    so_type => 'mRNA',
  },
  misc_RNA => {
    save => 1,
    transcript => 1,
    so_type => 'ncRNA',
  },
  tRNA => {
    save => 1,
    transcript => 1,
    so_type => 'tRNA',
  },
  snoRNA => {
    save => 1,
    transcript => 1,
    so_type => 'snoRNA',
  },
  snRNA => {
    save => 1,
    transcript => 1,
    so_type => 'snRNA',
  },
  rRNA => {
    save => 1,
    transcript => 1,
    so_type => 'rRNA',
  },
  LTR => {
    so_type => 'long_terminal_repeat',
  },
  repeat_region => {
    so_type => 'repeat_region',
  },
  "5'UTR" => {
    save => 1,
    so_type => 'five_prime_UTR',
    collected => 1,
  },
  "3'UTR" => {
    save => 1,
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

my %so_transcript_types = (pseudogenic_transcript => 1);

map {
  my $conf = $feature_loader_conf{$_};
  if ($conf->{transcript}) {
    $so_transcript_types{$conf->{so_type}} = 1;
  }
} keys %feature_loader_conf;

method prepare_transcript_data($transcript_uniquename, $gene_uniquename)
{
  my $data;

  if (defined $self->transcript_data()->{$transcript_uniquename}) {
    $data = $self->transcript_data()->{$transcript_uniquename};
  } else {
    $data = {};
    $self->transcript_data()->{$transcript_uniquename} = $data;
  }

  push @{$data->{"5'UTR_features"}}, ();
  push @{$data->{"3'UTR_features"}}, ();
  push @{$data->{"intron_features"}}, ();

  return $data;
}

method save_transcript($feature, $uniquename, $gene_uniquename)
{
  my $feat_type = $feature->primary_tag();
  my $so_type = $feature_loader_conf{$feat_type}->{so_type};

  if (!defined $uniquename) {
    warn "$feat_type feature has no uniquename\n";
    return;
  }

#  warn "SAVE_TRANSCRIPT: $uniquename\n";

  my $data = $self->prepare_transcript_data($uniquename, $gene_uniquename);

  $data->{bioperl_feature} = $feature;
  $data->{so_type} = $so_type;
  $data->{gene_uniquename} = $gene_uniquename;
  $data->{transcript_so_type} =
    $feature_loader_conf{$feat_type}->{so_type};
}

method save_utr($feature, $uniquename, $transcript_uniquename, $gene_uniquename)
{
  my $feat_type = $feature->primary_tag();
  my $so_type = $feature_loader_conf{$feat_type}->{so_type};

  my $data = $self->prepare_transcript_data($transcript_uniquename, $gene_uniquename);

  my %feature_data = (
    bioperl_feature => $feature,
    chado_feature => undef,
  );

  push @{$self->transcript_data()->{$transcript_uniquename}->{"${feat_type}_features"}},
       {%feature_data};
}

method process($feature, $chromosome)
{
  my $feat_type = $feature->primary_tag();
  my $so_type = $feature_loader_conf{$feat_type}->{so_type};

  if (!defined $so_type) {
    warn "no SO type for $feat_type - skipping\n";
    return;
  }

  if ($feature->has_tag("SO")) {
    my @so_quals = $feature->get_tag_values("SO");

    if (@so_quals > 1) {
      warn "more than one /SO= qualifier\n";
    }

    my $so_term = $self->find_cvterm_by_term_id($so_quals[0]);

    warn "found a /SO= qualifier for $so_quals[0]\n" if $self->verbose();

    if (defined $so_term) {
      warn "changing $so_type to ", $so_term->name(), "\n" if $self->verbose();
      $so_type = $so_term->name();
    } else {
      warn "can't find cvterm for: ", $so_quals[0], "\n";
    }
  }

  my ($uniquename, $transcript_uniquename, $gene_uniquename, $has_systematic_id) =
    $self->get_uniquename($feature, $so_type);

  warn "processing $feat_type $uniquename",
    defined $gene_uniquename ? " from gene: $gene_uniquename\n" : "\n";

  if ($feature_loader_conf{$feat_type}->{save}) {
    if ($so_type =~ /UTR/) {
      $self->save_utr($feature, $uniquename, $transcript_uniquename, $gene_uniquename);
    } else {
      $self->save_transcript($feature, $uniquename, $gene_uniquename);
    }
    return;
  }

  my $chado_feature =
    $self->store_feature_and_loc($feature, $chromosome, $so_type);

  if ($feature_loader_conf{$feat_type}->{collected}) {
    if (!$has_systematic_id) {
      warn "  $uniquename has no uniquename - skipping\n";
      return;
    }

    my %feature_data = (
      bioperl_feature => $feature,
      chado_feature => $chado_feature,
    );

    push @{$self->transcript_data()->{$transcript_uniquename}->{"${feat_type}_features"}},
         {%feature_data};
  }

  $self->process_qualifiers($feature, $chado_feature);

  return $chado_feature;
}

method store_product($bioperl_feature, $chado_feature, $uniquename)
{
  if ($bioperl_feature->has_tag("product")) {
    my @products = $bioperl_feature->get_tag_values("product");
    if (@products > 1) {
      warn "  $uniquename has more than one product\n";
    } else {
      if (length $products[0] == 0) {
        warn "  zero length product for $uniquename\n";
      } else {
        $self->qual_load()->process_product($chado_feature, $products[0]);
      }
    }
  } else {
    warn "  no product for $uniquename\n";
  }
}

method store_note($feature, $note)
{
  $self->store_featureprop($feature, 'comment', $note);
}

method store_ec_number($feature, $ec_number)
{
  $self->qual_load()->add_term_to_gene($feature, 'EC numbers',
                                       $ec_number, {}, 1);
}

my %colour_map = (
  2 => 'published',
  4 => 'transposon',
  6 => 'dubious',
  7 => 'biological_role_inferred',
  8 => 'sequence_orphan',
  10 => 'conserved_unknown',
  12 => 'fission_yeast_specific_family',
  13 => 'pseudogene',
);

method store_colour($feature, $colour)
{
  my $cvterm_name = $colour_map{$colour};

  if (!defined $cvterm_name) {
    warn "not storing /colour=$colour - unknown type\n";
    return;
  }

  if ($cvterm_name eq 'pseudogene') {
    if ($feature->type()->name() ne 'pseudogene') {
      warn $feature->uniquename(), " has /colour=13 but isn't a pseudogene\n";
    }

    return;
  }

  my $cvterm = $self->get_cvterm('PomBase gene characterisation status',
                                 $cvterm_name);

  $self->create_feature_cvterm($feature, $cvterm,
                               $self->objs()->{null_pub}, 0);
}

method get_target_curations($bioperl_feature)
{
  my @ret = ();

  if ($bioperl_feature->has_tag('controlled_curation')) {
    for my $cc ($bioperl_feature->get_tag_values('controlled_curation')) {
      my %qual_map = ();

      try {
        %qual_map = $self->split_sub_qualifiers($cc);
      } catch {
        warn "  $_: failed to process sub-qualifiers from $cc:\n";
      };

      my $term = delete $qual_map{term};

      if (defined $term && $term =~ /^target is /) {
        if ($term =~ /^target is (\S+)$/) {
          push @ret, { target => $1,
                       %qual_map };
        } else {
          warn "can't understand this target qualifier: $term\n";
        }
      }
    }
  }

  return @ret;
}

method process_qualifiers($bioperl_feature, $chado_object)
{
  my $type = $bioperl_feature->primary_tag();
  my $verbose = $self->verbose();

  my $uniquename = $chado_object->uniquename();

  my @target_curations = $self->get_target_curations($bioperl_feature);

  if ($bioperl_feature->has_tag("controlled_curation")) {
    for my $value ($bioperl_feature->get_tag_values("controlled_curation")) {
      my %unused_quals =
        $self->qual_load()->process_one_cc($chado_object, $bioperl_feature, $value,
                                           \@target_curations);
      warn "\n" if $verbose;
    }
  }

  my $chado_object_type = $chado_object->type()->name();

  my @tags = $bioperl_feature->all_tags();

  map { $self->{tag_counts}->{$chado_object_type}->{$_}++ } @tags;

  $self->{feature_counts}->{$chado_object_type}++;

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

  if ($chado_object_type eq 'gene' || $chado_object_type eq 'pseudogene') {
    if ($bioperl_feature->has_tag("EC_number")) {
      my @ec_numbers = $bioperl_feature->get_tag_values("EC_number");
      for my $ec_number (@ec_numbers) {
        $self->store_ec_number($chado_object, $ec_number);
      }

      if ($type ne 'CDS') {
        warn "$uniquename $type has ", scalar(@ec_numbers), " /EC_number qualifier(s)"
      }
    }

    if ($bioperl_feature->has_tag("colour")) {
      my @colours = $bioperl_feature->get_tag_values("colour");

      if (@colours > 1) {
        warn "$type $uniquename has ", scalar(@colours), " /colours qualifier(s)"
      }

      $self->store_colour($chado_object, $colours[0]);
    }
  } else {
    if ($bioperl_feature->has_tag("GO")) {
      for my $value ($bioperl_feature->get_tag_values("GO")) {
        my %unused_quals =
          $self->qual_load()->process_one_go_qual($chado_object, $bioperl_feature, $value);
        warn "\n" if $verbose;
      }
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
    my $prefix = "$uniquename:$so_type:";
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

method store_transcript_parts($bioperl_cds, $chromosome,
                              $transcript_so_type,
                              $utrs_5_prime, $utrs_3_prime, $introns)
{
  my $uniquename = ($bioperl_cds->get_tag_values('systematic_id'))[0];
  if ($uniquename !~ /\.\d$/) {
    $uniquename .= '.1';
  }

  my $chado = $self->chado();
  my $cds_location = $bioperl_cds->location();
  my $transcript_start = $cds_location->start();
  my $transcript_end = $cds_location->end();

  my @utrs_data = (@$utrs_5_prime, @$utrs_3_prime);

  for my $utr_data (@utrs_data) {
    my $featureloc = $utr_data->{bioperl_feature}->location();
    my $utr_start = $featureloc->start();
    my $utr_end = $featureloc->end();

    if ($utr_start < $transcript_start) {
      $transcript_start = $utr_start;
    }
    if ($utr_end > $transcript_end) {
      $transcript_end = $utr_end;
    }
  }

  my $exon_so_type;

  if ($bioperl_cds->has_tag('pseudo')) {
    $transcript_so_type = 'pseudogenic_transcript';
    $exon_so_type = 'pseudogenic_exon';
  } else {
    $exon_so_type = 'exon';
  }

  my $chado_transcript = $self->store_feature($uniquename, undef, [],
                                        $transcript_so_type);
  my $strand = $bioperl_cds->location()->strand();
  $self->store_location($chado_transcript, $chromosome, $strand,
                        $transcript_start, $transcript_end);

  my @exons = $self->store_feature_parts($uniquename, $bioperl_cds,
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
    my $chado_peptide = $self->store_feature("$uniquename:pep", undef,
                                             [], 'polypeptide');

    $self->store_feature_rel($chado_peptide, $chado_transcript, 'derives_from');

    $self->store_location($chado_peptide, $chromosome, $strand,
                          $transcript_start, $transcript_end);

    $self->store_product($bioperl_cds, $chado_peptide, $uniquename);
  } else {
    $self->store_product($bioperl_cds, $chado_transcript, $uniquename);
  }

  return ($transcript_start, $transcript_end, $chado_transcript);
}


method finalise($chromosome)
{
  while (my ($uniquename, $feature_data) = each %{$self->transcript_data()}) {
    my $gene_start = 9999999999;
    my $gene_end = -1;

    my $so_type = $feature_data->{so_type};

    if (!$so_type) {
      use Data::Dumper;
      $Data::Dumper::Maxdepth = 5;
      warn 'no SO type:', Dumper([$feature_data]), "\n";
    }

    my $transcript_bioperl_feature = $feature_data->{bioperl_feature};

    my $transcript_so_type = $feature_data->{transcript_so_type};


    if (!defined $transcript_bioperl_feature) {
      die "no feature for $uniquename\n";
    }

    warn "processing $so_type $uniquename\n";

    my ($transcript_start, $transcript_end, $chado_transcript) =
      $self->store_transcript_parts($transcript_bioperl_feature,
                                    $chromosome,
                                    $transcript_so_type,
                                    $feature_data->{"5'UTR_features"},
                                    $feature_data->{"3'UTR_features"},
                                    $feature_data->{"intron_features"},
                                  );

    if ($transcript_start < $gene_start) {
      $gene_start = $transcript_start;
    }

    if ($transcript_end > $gene_end) {
      $gene_end = $transcript_end;
    }

    $self->process_qualifiers($transcript_bioperl_feature, $chado_transcript);

    my $gene_uniquename = $feature_data->{gene_uniquename};
    my $chado_gene = $self->gene_objects()->{$gene_uniquename};

    if (!defined $chado_gene) {
      $chado_gene = $self->store_feature_and_loc($transcript_bioperl_feature,
                                                 $chromosome, 'gene',
                                                 $gene_start, $gene_end);
      $self->gene_objects()->{$gene_uniquename} = $chado_gene;

      $self->process_qualifiers($transcript_bioperl_feature, $chado_gene);
    }

    $self->store_feature_rel($chado_transcript, $chado_gene, 'part_of');
  }

  warn "counts of EMBL qualifiers by feature type:\n";

  for my $feat_type (keys %{$self->{tag_counts}}) {
    my %counts = %{$self->{tag_counts}->{$feat_type}};

    my $feat_count = $self->{feature_counts}->{$feat_type};

    warn "  $feat_type ($feat_count)\n";

    for my $tag_name (keys %counts) {
      my $count = $counts{$tag_name};
      warn "    $tag_name: $count\n";
    }
  }
}
