package PomBase::Role::SeqTranslate;

=head1 NAME

PomBase::Role::SeqTranslate - Translate DNA to protein

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::SeqTranslate

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

use Bio::Seq;

=head2 translate

 Usage   : with 'PomBase::Role::SeqTranslate'; my $protein = $self->translate('agtctg');
 Function: Return the translation of a DNA string
 Args    : $seq_str - the dna/rna sequence
 Return  : protein sequence

=cut

method translate($seq_str)
{
  my $seq_obj = Bio::Seq->new(-seq => $seq_str,
                              -alphabet => 'dna');

  return $seq_obj->translate()->seq();
}
