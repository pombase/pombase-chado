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
use Bio::Tools::pICalculator;
use Bio::Tools::CodonOptTable;

use Moose::Role;

method translate_sequence($residues, $phase, $is_mito) {
  my $seq = Bio::Seq->new(-seq => $residues, -alphabet => 'dna');

  my $genetic_code = $is_mito ? 4 : 1;

  my $prot_seq = $seq->translate(undef, undef, $phase, $genetic_code);
  my $seq_stats = Bio::Tools::SeqStats->new(-seq => $prot_seq);
  my $number_of_residues = length($prot_seq->seq());
  my $weight = $seq_stats->get_mol_wt();
  my $pIcalc = Bio::Tools::pICalculator->new(-places => 2);
  $pIcalc->seq($prot_seq);
  my $charge_at_ph7 = $pIcalc->charge_at_pH(7);
  my $isoelectric_point = $pIcalc->iep();

  my $cai_seqobj = Bio::Tools::CodonOptTable->new(
    -seq              => $residues,
    -alphabet         => 'dna',
    -is_circular      => 0,
    -genetic_code     => $genetic_code,
  );

  my $codon_adaptation_index = $cai_seqobj->calculate_cai($cai_seqobj->rscu_rac_table());

  my $stats = {
    molecular_weight => $weight->[0],
    average_residue_weight => int(100 * $weight->[0] / $number_of_residues) / 100.0,
    charge_at_ph7 => int($charge_at_ph7 * 100) / 100.0,
    codon_adaptation_index => $codon_adaptation_index,
    isoelectric_point => $isoelectric_point,
  };

  return ($prot_seq->seq(), $stats);
}

1;
