package PomBase::Role::FeatureSubsequence;

=head1 NAME

PomBase::Role::FeatureSubsequence - Code for retrieving the (sub)sequence of a
   feature

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::FeatureSubsequence

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose::Role;

=head2 feature_subseq

 Usage   : my $seq = $object->feature_subseq($mrna, $start, $end)
 Function: Return a sub-sequence of an mRNA by assembly the sequence from
           the exons of the transcript.
 Args    : $mrna - a Sequence::Feature with SO type "mRNA"
           $start, $end - the start and end in 1-based coordinates
 Return  : an RNA string

=cut

method feature_subseq($feature, $start, $end)
{
  if ($start <= 0) {
    die "start position $start is less than 1 in feature_subseq()";
  }
  if ($end <= 0) {
    die "end position $end is less than 1 in feature_subseq()";
  }

  if ($start > $end) {
    die "start position $start is greater than end position $end in feature_subseq()";
  }

  if ($feature->type()->name() ne 'mRNA') {
    die "can't call feature_subseq() with feature type: ",
      $feature->type()->name(), ' - must be "mRNA"';
  }

  my $exon_rel_rs = $feature->feature_relationship_objects()
    ->search({ 'type.name' => 'exon' },
             { join => { subject => 'type' },
               prefetch => 'subject',
               order_by => 'rank' });

  state $chr_seqs = {};

  my $mrna_sequence = '';

  while (my $exon_rel = $exon_rel_rs->next()) {
    my $exon = $exon_rel->subject();

    my $loc_rs = $exon->featureloc_features();

    my $loc = $loc_rs->next();
    my $chr_sequence = undef;

    if ($chr_seqs->{$loc->srcfeature_id()}) {
      $chr_sequence = $chr_seqs->{$loc->srcfeature_id()};
    } else {
      $chr_sequence = $loc->srcfeature()->residues();
      $chr_seqs->{$loc->srcfeature_id()} = $chr_sequence;
    }

    my $sub_seq = substr($chr_sequence, $loc->fmin(), $loc->fmax() - $loc->fmin());

    if ($loc->strand() == -1) {
      $sub_seq = reverse $sub_seq;
      $sub_seq =~ tr/ACGTacgt/TGCAtgca/;
    }

    $mrna_sequence .= $sub_seq;

    if (defined $loc_rs->next()) {
      die "internal error - exon ", $exon->uniquename(), " has more than location";
    }
  }

  if ($end > length $mrna_sequence) {
    die "end position $end out of range in feature_subseq()";
  }

  return substr($mrna_sequence, $start - 1, $end - $start + 1);
}

1;
