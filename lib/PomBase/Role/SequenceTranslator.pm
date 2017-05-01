package PomBase::Role::SequenceTranslator;

=head1 NAME

PomBase::Role::SequenceTranslator - a role for calling BioPerl to translate
                                    an mRNA sequence

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::SequenceTranslator

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2017 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;

use Bio::Seq;
use Bio::Tools::SeqStats;

use Moose::Role;

method translate_sequence($residues, $phase, $is_mito) {
  my $seq = Bio::Seq->new(-seq => $residues, -alphabet => 'dna');

  my $prot_seq = $seq->translate(undef, undef, $phase, $is_mito ? 4 : 1);
  my $seq_stats = Bio::Tools::SeqStats->new(-seq => $prot_seq);
  my $weight = $seq_stats->get_mol_wt();

  return ($prot_seq->seq(), $weight->[0]);
}

1;
