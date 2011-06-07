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
  },
  LTR => {
    so_type => 'long_terminal_repeat',
  },
  repeat_region => {
    so_type => 'repeat_region',
  },
  misc_RNA => {
    so_type => 'gene',
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
    intron => 'intron',
    collected => 1,
  },
  "intron" => {
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
);

method process($feature, $chromosome)
{
  my $feat_type = $feature->primary_tag();
  my ($uniquename, $gene_uniquename) = $self->get_uniquename($feature);

  my $so_type = $feature_loader_conf{$feat_type}->{so_type};

  print "processing $feat_type $uniquename\n";

  if ($feature_loader_conf{$feat_type}->{save}) {
    my %new_data = (
      bioperl_feature => $feature,
      so_type => $so_type,
    );

    push @{$new_data{"5'UTR_features"}}, ();
    push @{$new_data{"3'UTR_features"}}, ();
    push @{$new_data{"intron"}}, ();

    $self->gene_data()->{$uniquename} = { %new_data };
    return;
  }

  my $chado_feature =
    $self->store_feature_and_loc($feature, $chromosome, $so_type);

  if ($feature_loader_conf{$feat_type}->{collected}) {
    my %feature_data = (
      bioperl_feature => $feature,
      chado_feature => $chado_feature,
    );
    push @{$self->gene_data()->{$gene_uniquename}->{"${feat_type}_features"}},
         {%feature_data}
  }

  $self->process_qualifiers($feature, $chado_feature);

  return $chado_feature;
}

method store_product($feature, $product)
{
  $self->store_featureprop($feature, 'product', $product);
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

  if ($bioperl_feature->has_tag("db_xref")) {
    for my $dbxref_value ($bioperl_feature->get_tag_values("db_xref")) {
      $self->add_feature_dbxref($chado_object, $dbxref_value);
    }
  }
}

method store_exons($uniquename, $bioperl_cds, $chromosome, $so_type)
{
  my $chado = $self->chado();

  my @coords_list = $self->coords_of_feature($bioperl_cds);
  my @exons = ();

  for (my $i = 0; $i < @coords_list; $i++) {
    my ($start, $end) = @{$coords_list[$i]};
    my $exon_uniquename = $uniquename . ':exon:' . ($i + 1);
    my $chado_exon = $self->store_feature($exon_uniquename, undef, [], $so_type);

    push @exons, $chado_exon;

    my $strand = $bioperl_cds->location()->strand();

    $self->store_location($chado_exon, $chromosome, $strand, $start, $end);
  }

  return @exons;
}

method store_gene_parts($uniquename, $bioperl_cds, $chromosome,
                        $utrs_5_prime, $utrs_3_prime)
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

  my $mrna_uniquename = "$uniquename.1";
  my $mrna_so_type;

  if ($bioperl_cds->has_tag('pseudo')) {
    $mrna_so_type = 'pseudogenic_transcript';
    $exon_so_type = 'pseudogenic_exon';
  } else {
    $mrna_so_type = 'mRNA';
    $exon_so_type = 'exon';
  }

  my $chado_mrna = $self->store_feature($mrna_uniquename, undef, [],
                                        $mrna_so_type);
  my $strand = $bioperl_cds->location()->strand();
  $self->store_location($chado_mrna, $chromosome, $strand,
                        $gene_start, $gene_end);

  my @exons = $self->store_exons($mrna_uniquename, $bioperl_cds, $chromosome,
                                 $exon_so_type);

  for my $exon (@exons) {
    $self->store_feature_rel($chado_mrna, $exon, 'part_of');
  }

  for my $utr (@$utrs_5_prime) {
    $self->store_feature_rel($chado_mrna, $utr->{chado_feature}, 'part_of');
  }

  for my $utr (@$utrs_3_prime) {
    $self->store_feature_rel($chado_mrna, $utr->{chado_feature}, 'part_of');
  }

  return ($gene_start, $gene_end, $chado_mrna);
}


method finalise($chromosome)
{
  while (my ($uniquename, $feature_data) = each %{$self->gene_data()}) {
    my $bioperl_feature = $feature_data->{bioperl_feature};
    my $so_type = $feature_data->{so_type};
    my @utr_5_prime_features = @{$feature_data->{"5'UTR_features"}};
    my @utr_3_prime_features = @{$feature_data->{"3'UTR_features"}};

    my ($gene_start, $gene_end, $chado_mrna) =
      $self->store_gene_parts($uniquename,
                              $bioperl_feature,
                              $chromosome,
                              [@utr_5_prime_features],
                              [@utr_3_prime_features],
                             );

    my $chado_gene =
      $self->store_feature_and_loc($bioperl_feature, $chromosome, $so_type,
                                   $gene_start, $gene_end);

    $self->process_qualifiers($bioperl_feature, $chado_gene);

    $self->store_feature_rel($chado_gene, $chado_mrna, 'part_of');
  }
}
