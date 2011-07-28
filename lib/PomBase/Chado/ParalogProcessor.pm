package PomBase::Chado::ParalogProcessor;

=head1 NAME

PomBase::Chado::ParalogProcessor - Code for storing paralogs

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::ParalogProcessor

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

has chado => (is => 'ro');
has verbose => (is => 'ro');

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::ChadoObj';
with 'PomBase::Role::Embl::FeatureRelationshippropStorer';

method store_all_paralogs($paralog_data)
{
  warn "    process_ortholog()\n" if $self->verbose();
  my $org_name;
  my $gene_bit;

  my $pombe = $self->find_organism_by_common_name('pombe') || die;

  while (my ($gene, $data_list) = each %$paralog_data) {

    for my $data (@$data_list) {
      my $feature = $data->{feature} || die;
      my $other_gene_names = $data->{other_gene_names};
      my @other_gene_names = @$other_gene_names;
      my $related = $data->{related};
      my $date = $data->{date};

      for my $other_gene_name (@other_gene_names) {
        try {
          my $other_gene_feature =
          $self->find_chado_feature($other_gene_name, 1, 1, $pombe);


          warn "    creating paralog from ", $gene,
          " to $other_gene_name\n" if $self->verbose();

          my $rel_rs = $self->chado()->resultset('Sequence::FeatureRelationship');

          my $orth_guard = $self->chado()->txn_scope_guard;
          my $rel = $rel_rs->create({ object_id => $feature->feature_id(),
                                      subject_id => $other_gene_feature->feature_id(),
                                      type_id => $self->objs()->{paralogous_to_cvterm}->cvterm_id()
                                    });

          if (defined $date) {
            $self->store_feature_relationshipprop($rel, date => $date);
          }

          if ($related) {
            $self->store_feature_relationshipprop($rel, 'homology_type' => 'distant');
          }

          $orth_guard->commit();
          warn "  created paralog to $other_gene_name\n" if $self->verbose();
        } catch {
          warn "  failed to create paralog relation from ", $feature->uniquename(),
          " to $other_gene_name: $_\n";
        }
      }
    }
  }
}
