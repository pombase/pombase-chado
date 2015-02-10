package PomBase::Role::LegacyAlleleHandler;

=head1 NAME

PomBase::Role::LegacyAlleleHandler - Deal with extracting useful info from
                                     allele names and descriptions

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::LegacyAlleleHandler

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use Moose::Role;

=head2 is_aa_mutation_desc

 Usage   : if ($self->is_aa_mutation_desc($description)) { ... }
 Function: Return true if the $description looks like an amino acid
           mutation, like; "K10A" and doesn't look like a nucleotide
           mutation description like "A10T"

=cut
sub is_aa_mutation_desc
{
  my $self = shift;
  my $description = shift;

  return 0 unless defined $description;

  $description = $description->trim();

  my $seen_aa_desc = 0;

  if ($description =~ /,/) {
    for my $bit (split /,/, $description) {
      $bit = $bit->trim();
      if (_could_be_aa_mutation_desc($bit)) {
        if (!_is_na_mutation_desc($bit)) {
          $seen_aa_desc = 1;
        }
      } else {
        return 0;
      }
    }

    return $seen_aa_desc;
  }

  return _could_be_aa_mutation_desc($description) && !_is_na_mutation_desc($description);
}

sub allele_type_from_desc
{
  my ($self, $description, $gene_name) = @_;

  $description =~ s/^\s+//;
  $description =~ s/\s+$//;

  if (grep { $_ eq $description } ('deletion', 'wild_type', 'wild type', 'unknown', 'other', 'unrecorded')) {
    return ($description =~ s/\s+/_/r);
  } else {
    if ($self->is_aa_mutation_desc($description)) {
      return 'amino_acid_mutation';
    } else {
      if ($description =~ /^[A-Z]\d+->(amber|ochre|opal|stop)$/i) {
        return 'nonsense_mutation';
      } else {
        if (defined $gene_name && $description =~ /^$gene_name/) {
          return 'other';
        }
      }
    }
  }

  return undef;
}

1;
