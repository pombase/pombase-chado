package PomBase::Retrieve::Orthologs;

=head1 NAME

PomBase::Retrieve::Orthologs - Retrieve orthologs from Chado

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::Orthologs

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

use List::Gen 'iterate';

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::CvQuery';

method retrieve() {
  my $chado = $self->chado();

  my $it = do {
    my $orthologous_to_cvterm = $self->get_cvterm('sequence', 'orthologous_to');

    my $results =
      $chado->resultset('Sequence::FeatureRelationship')
        ->search({ 'me.type_id' => $orthologous_to_cvterm->cvterm_id() },
                 { prefetch => [ 'subject', 'object' ],
                   order_by => 'subject_id' });

    iterate {
      my $row = $results->next();
      if (defined $row) {
        my $subject = $row->subject();
        my $object = $row->object();
        return [$subject->uniquename(), $object->uniquename()];
      } else {
        return undef;
      }
    };
  };
}

with 'PomBase::Retriever';

1;
