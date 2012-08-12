package PomBase::Role::PhenotypeFeatureFinder;

=head1 NAME

PomBase::Role::PhenotypeFeatureFinder - Code for finding and creating allele

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::PhenotypeFeatureFinder

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose::Role;


method get_gene($gene_data)
{
  if (!defined $gene_data) {
    croak 'no $gene_data passed to _get_gene()';
  }
  my $gene_uniquename = $gene_data->{uniquename};
  my $organism_name = $gene_data->{organism};
  my $organism = $self->find_organism_by_full_name($organism_name);

  return $self->find_chado_feature($gene_uniquename, 1, 1, $organism);
}

method get_transcript($gene_data)
{
  my $gene_uniquename = $gene_data->{uniquename};
  my $organism_name = $gene_data->{organism};
  my $organism = $self->find_organism_by_full_name($organism_name);

  return $self->find_chado_feature("$gene_uniquename.1", 1, 1, $organism);
}

method get_allele($allele_data)
{
  my $allele;
  my $gene = $self->get_gene($allele_data->{gene});
  if ($allele_data->{type} eq 'existing') {
    $allele = $self->chado()->resultset('Sequence::Feature')
                   ->find({ uniquename => $allele_data->{primary_identifier},
                            organism_id => $gene->organism()->organism_id() });
    if (!defined $allele) {
      use Data::Dumper;
      die "failed to create allele from: ", Dumper([$allele_data]);
    }
  } else {
    my $gene_uniquename = $gene->uniquename();

    my $new_uniquename = $self->get_new_uniquename($gene_uniquename . ':allele-', 1);
    $allele = $self->store_feature($new_uniquename,
                                   $allele_data->{name}, [], 'allele',
                                   $gene->organism());

    $self->store_feature_rel($allele, $gene, 'instance_of');

    if (defined $allele_data->{description}) {
      $self->store_featureprop($allele, 'description', $allele_data->{description});
    }
  }

  return $allele;
}

1;
