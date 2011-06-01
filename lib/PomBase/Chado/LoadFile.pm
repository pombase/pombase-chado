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

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::FeatureStorer';
with 'PomBase::Role::Embl::Located';
with 'PomBase::Role::CoordCalculator';
with 'PomBase::Role::Embl::SystematicID';

has verbose => (is => 'ro', isa => 'Bool');
has organism => (is => 'ro',
                 required => 1,
                );
has delayed_features => (is => 'ro', isa => 'HashRef',
                         init_arg => undef,
                         default => sub { {} },
                        );

method process_file($file)
{
  my $chado = $self->chado();
  my $verbose = $self->verbose();
  my $config = $self->config();

  my $qual_load = PomBase::Chado::QualifierLoad->new(chado => $chado,
                                                     verbose => $verbose,
                                                     config => $config
                                                   );

  my %feature_loader_conf = (
    CDS => 'gene',
    LTR => 'repeat_region',   # XXX should LTR fold into repeat_region?
    repeat_region => 'repeat_region',
    misc_RNA => 'gene',
    "5'UTR" => undef,
    "3'UTR" => undef,
    "exon" => undef,
    "intron" => undef,
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

  print "reading database from $display_id\n";

  my $anno_collection = $seq_obj->annotation;

  my %no_systematic_id_counts = ();

  for my $bioperl_feature ($seq_obj->get_SeqFeatures) {
    my $type = $bioperl_feature->primary_tag();

    my $uniquename = $self->get_uniquename($bioperl_feature);

    warn "processing $type $uniquename\n";

    if (!defined $feature_loaders{$type}) {
      warn "no processor for $type";
      next;
    }

    my $chado_object =
      $feature_loaders{$type}->process($bioperl_feature, $display_id,
                                       $self->delayed_features());

    next unless defined $chado_object;

    if ($bioperl_feature->has_tag("controlled_curation")) {
      for my $value ($bioperl_feature->get_tag_values("controlled_curation")) {
        my %unused_quals =
          $qual_load->process_one_cc($chado_object, $bioperl_feature, $value);
        $qual_load->check_unused_quals($value, %unused_quals);
        warn "\n" if $verbose;
      }
    }

    if ($bioperl_feature->has_tag("GO")) {
      for my $value ($bioperl_feature->get_tag_values("GO")) {
        my %unused_quals =
          $qual_load->process_one_go_qual($chado_object, $bioperl_feature, $value);
        $qual_load->check_unused_quals($value, %unused_quals);
        warn "\n" if $verbose;
      }
    }

    if ($type eq 'CDS') {
      if ($bioperl_feature->has_tag("product")) {
        my @products = $bioperl_feature->get_tag_values("product");
        if (@products > 1) {
          warn "  $uniquename has more than one product\n";
        } else {
          if (length $products[0] == 0) {
            warn "  zero length product for $uniquename\n";
          }
        }
      } else {
        warn "  no product for $uniquename\n";
      }
    }
  }

  $self->finalise();

  warn "counts of features that have no systematic_id, by type:\n";

  for my $type_key (keys %no_systematic_id_counts) {
    warn "$type_key ", $no_systematic_id_counts{$type_key}, "\n";
  }
  warn "\n";
}

method finalise
{
  while (my ($uniquename, $feature_data) = each %{$self->delayed_features()}) {
    my $feature = $feature_data->{feature};
    my @collected_features = @{$feature_data->{collected_features}};

    die unless $feature;

    my @coords = ();
    push @coords,
      map {
        $self->coords_of_feature($_);
      } grep {
        $_->primary_tag() eq "5'UTR";
      } @collected_features;
    push @coords, $self->coords_of_feature($feature);
    push @coords,
      map {
        $self->coords_of_feature($_);
      } grep {
        $_->primary_tag() eq "3'UTR";
      } @collected_features;

    $self->store_feature($feature, $feature_data->{so_type}, [@coords]);
  }
}

1;
