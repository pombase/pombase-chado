package PomBase::Import::MalaCards;

=head1 NAME

PomBase::Import::MalaCards - Read MalaCards data and store disease annotations

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::MalaCards

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

use Text::CSV;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::CvtermpropStorer';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef');

has destination_taxonid => (is => 'rw', init_arg => undef);
has human_ortholog_map => (is => 'rw', init_arg => undef);

method BUILD {
  my $destination_taxonid = undef;

  my @opt_config = ('destination-taxonid=s' => \$destination_taxonid);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $destination_taxonid) {
    die "the --destination-taxonid argument is required\n";
  }

  $self->destination_taxonid($destination_taxonid);

  my $chado = $self->chado();

  my $dest_organism = $self->find_organism_by_taxonid($destination_taxonid);
  my $human = $self->find_organism_by_common_name('human');

  my $orthologs_rs = $chado->resultset('Sequence::FeatureRelationship')
    ->search({
      -or => {
        -and => {
          'subject.organism_id' => $dest_organism->organism_id(),
          'object.organism_id' => $human->organism_id(),
        },
        -and => {
          'subject.organism_id' => $human->organism_id(),
          'object.organism_id' => $dest_organism->organism_id(),
        },
      }
    }, { join => ['subject', 'object'] });

  my %human_ortholog_map = ();

  while (defined (my $ortholog_rel = $orthologs_rs->next())) {
    my $dest_gene = undef;
    my $human_gene = undef;

    if ($ortholog_rel->subject()->organism_id() == $human->organism_id()) {
      $dest_gene = $ortholog_rel->object();
      $human_gene = $ortholog_rel->subject();
    } else {
      $human_gene = $ortholog_rel->object();
      $dest_gene = $ortholog_rel->subject();
    }

    if ($human_gene->name()) {
      $human_ortholog_map{$human_gene->name()} = $dest_gene;
    } else {
      die "human gene with no name, id: ", $human_gene->uniquename();
    }
  }

  $self->human_ortholog_map(\%human_ortholog_map);
}

my %details_by_do_id = ();

method load($fh) {
  my $chado = $self->chado();

  my $tsv = Text::CSV->new({ sep_char => "\t" });

  my $pub = $self->find_or_create_pub('PMID:27899610');

  my %seen_annotations = ();

  while (my $columns_ref = $tsv->getline($fh)) {
    if (@$columns_ref == 1 && $columns_ref->[0]->trim()->length() == 0) {
      next;
    }
    my ($malacards_disease_name, $malacards_disease_slug,
        $malacards_displayed_disease_name, $human_gene_name, $do_id) =
      map { $_->trim() || undef } @$columns_ref;

    my $dest_gene = $self->human_ortholog_map()->{$human_gene_name};

    if (defined $dest_gene) {
      if (!defined $do_id) {
        warn "no DO ID for $malacards_disease_slug -> $human_gene_name " .
          "(", $dest_gene->uniquename(), ")\n";
        next;
      }

      my $cvterm = $self->find_cvterm_by_term_id($do_id);

      if (!defined $cvterm) {
        warn "could not create cvterm for $do_id, skipping $malacards_disease_slug\n";
        next;
      }

      if (!exists $details_by_do_id{$do_id}) {
        $details_by_do_id{$do_id} = {
          malacards_disease_name => $malacards_disease_name,
          malacards_displayed_disease_name => $malacards_displayed_disease_name,
          malacards_disease_slug => $malacards_disease_slug,
          cvterm => $cvterm,
        };
      }

      my $key = "$do_id -> " . $dest_gene->uniquename();

      if (!$seen_annotations{$key}) {
        $self->create_feature_cvterm($dest_gene, $cvterm, $pub, 0);
        $seen_annotations{$key} = 1;
      }
    }
  }

  while (my ($do_id, $details) = each %details_by_do_id) {
    my $cvterm = $details->{cvterm};
    for my $prop_name (qw(malacards_disease_name malacards_displayed_disease_name malacards_disease_slug)) {
      $self->store_cvtermprop($cvterm, $prop_name, $details->{$prop_name});
    }
  }

}

1;
