package PomBase::Chado::LoadFile;

=head1 NAME

PomBase::Chado::LoadFile - Load an EMBL file into Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::LoadFile

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

use PomBase::Chado::LoadFeat;
use Tie::Hash::Indexed;
use Digest::MD5;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::CoordCalculator';
with 'PomBase::Role::Embl::SystematicID';
with 'PomBase::Role::Embl::FeatureRelationshipStorer';

has verbose => (is => 'ro', isa => 'Bool');
has organism => (is => 'ro',
                 required => 1,
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
}

method process_file($file)
{
  my $chado = $self->chado();
  my $verbose = $self->verbose();
  my $config = $self->config();

  my %feature_loader_conf = (
    CDS => 'gene',
    LTR => 'repeat_region',   # XXX should LTR fold into repeat_region?
    repeat_region => 'repeat_region',
    misc_RNA => 'gene',
    "5'UTR" => 'five_prime_UTR',
    "3'UTR" => 'three_prime_UTR',
    "exon" => undef,
    "intron" => "intron",
    "misc_feature" => 'region',
    "gap" => 'gap',
    "conflict" => 'sequence_conflict',
  );

  my %feature_loaders =
    map {
      my $embl_type = $_;
      my $so_type = $feature_loader_conf{$embl_type};

      ($embl_type, PomBase::Chado::LoadFeat->new(embl_type => $embl_type,
                                                 organism => $self->organism(),
                                                 config => $self->config(),
                                                 chado => $self->chado(),
                                                 so_type => $so_type));
    } keys %feature_loader_conf;

  my $io = Bio::SeqIO->new(-file => $file, -format => "embl" );
  my $seq_obj = $io->next_seq;

  my $display_id = $seq_obj->display_id();
  my $chromosome_cvterm = $self->get_cvterm('sequence', 'chromosome');
  my $md5 = Digest::MD5->new;
  $md5->add($seq_obj->seq());

  my %create_args = (
    type_id => $chromosome_cvterm->cvterm_id(),
    uniquename => $display_id,
    name => undef,
    organism_id => $self->organism()->organism_id(),
    residues => $seq_obj->seq(),
    seqlen => length $seq_obj->seq(),
    md5checksum => $md5->hexdigest(),
  );

  my $chromosome =
    $chado->resultset('Sequence::Feature')->create({%create_args});

  print "reading database from $display_id\n";

  my $anno_collection = $seq_obj->annotation;

  my %no_systematic_id_counts = ();

  for my $bioperl_feature ($seq_obj->get_SeqFeatures) {
    my $type = $bioperl_feature->primary_tag();

    my ($uniquename) = $self->get_uniquename($bioperl_feature);

    print "processing $type $uniquename\n";

    if (!defined $feature_loaders{$type}) {
      warn "no processor for $type";
      next;
    }

    my $chado_object =
      $feature_loaders{$type}->process($bioperl_feature, $chromosome,
                                       $self->gene_data());

    next unless defined $chado_object;

    $self->process_qualifiers($bioperl_feature, $chado_object);
  }

  $self->finalise($chromosome);
}

method store_exons($uniquename, $bioperl_cds, $chromosome)
{
  my $chado = $self->chado();

  my @coords_list = $self->coords_of_feature($bioperl_cds);
  my @exons = ();

  for (my $i = 0; $i < @coords_list; $i++) {
    my ($start, $end) = @{$coords_list[$i]};

    my $exon_uniquename = $uniquename . ':exon:' . ($i + 1);

    my $chado_exon = $self->store_feature($exon_uniquename, undef, [], 'exon');

    push @exons, $chado_exon;

    my $strand = $bioperl_cds->location()->strand();
    my $fmin = $start - 1;
    my $fmax = $end;

    $self->store_location($chado_exon, $chromosome, $strand, $fmin, $fmax);
  }

  return @exons;
}

method store_gene_parts($uniquename, $bioperl_cds, $chromosome,
                        $utrs_5_prime, $utrs_3_prime)
{
  my $chado = $self->chado();

  my $cds_location = $bioperl_cds->location();

  my $gene_fmin = $cds_location->start() - 1;
  my $gene_fmax = $cds_location->end();

  my @utrs_data = (@$utrs_5_prime, @$utrs_3_prime);

  for my $utr_data (@utrs_data) {
    my $featureloc = $utr_data->{chado_feature}->featureloc_features()->first();
    my $utr_fmin = $featureloc->fmin();
    my $utr_fmax = $featureloc->fmax();

    if ($utr_fmin < $gene_fmin) {
      $gene_fmin = $utr_fmin;
    }
    if ($utr_fmax > $gene_fmax) {
      $gene_fmax = $utr_fmax;
    }
  }

  my $mrna_uniquename = "$uniquename.1";

  my $chado_mrna = $self->store_feature($mrna_uniquename, undef, [], 'mRNA');
  my $strand = $bioperl_cds->location()->strand();
  $self->store_location($chado_mrna, $chromosome, $strand,
                        $gene_fmin, $gene_fmax);

  my @exons = $self->store_exons($mrna_uniquename, $bioperl_cds, $chromosome);

  for my $exon (@exons) {
    $self->store_feature_rel($chado_mrna, $exon, 'part_of');
  }

  for my $utr (@$utrs_5_prime) {
    $self->store_feature_rel($chado_mrna, $utr->{chado_feature}, 'part_of');
  }

  for my $utr (@$utrs_3_prime) {
    $self->store_feature_rel($chado_mrna, $utr->{chado_feature}, 'part_of');
  }

  return ($gene_fmin, $gene_fmax, $chado_mrna);
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
