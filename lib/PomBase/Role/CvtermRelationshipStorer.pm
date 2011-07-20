package PomBase::Role::CvtermRelationshipStorer;

=head1 NAME

PomBase::Role::CvtermRelationshipStorer - Code for store rows in the
                                          cvterm_relationship table

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::CvtermRelationshipStorer

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose::Role;

requires 'chado';

method store_cvterm_rel($subject, $object, $rel)
{
  $self->chado()->resultset('Cv::CvtermRelationship')
    ->create({ subject_id => $subject->cvterm_id(),
               object_id => $object->cvterm_id(),
               type_id => $rel->cvterm_id(),
             });
}

1;
