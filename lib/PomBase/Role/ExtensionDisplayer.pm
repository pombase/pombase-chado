package PomBase::Role::ExtensionDisplayer;

=head1 NAME

PomBase::Role::ExtensionDisplayer - Code for creating a human readable (GAF file
                                    style) from an annotation extension.

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::ExtensionDisplayer

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

use PomBase::Chado;

requires 'chado';

method make_gaf_extension($feature_cvterm)
{
  my $extension_term = $feature_cvterm->cvterm();

  my $parent_rels_rs =
    $self->chado()->resultset("Cv::CvtermRelationship")->
    search({ 'subject_id' => $extension_term->cvterm_id() },
           {
             prefetch => [{ object => { dbxref => 'db' } }, 'type'],
           });

  my @parents = ();

  while (defined (my $rel = $parent_rels_rs->next())) {
    if ($rel->type()->name() ne 'is_a') {
      push @parents, { rel_type_name => $rel->type()->name(),
                       detail => PomBase::Chado::id_of_cvterm($rel->object()) };
    }
  }

  my $annotation_ex_prefix = "annotation_extension_relation-";

  my $props_rs =
    $feature_cvterm->cvterm()->cvtermprops()->
    search({ 'type.name' => { -like => "$annotation_ex_prefix%" }, },
           { join => 'type' });

  while (defined (my $prop = $props_rs->next())) {
    if ($prop->type()->name() =~ /^$annotation_ex_prefix(.*)/) {
      push @parents, { rel_type_name => $1,
                       detail => $prop->value() };
    } else {
      die "internal error - unexpected name: ", $prop->type()->name();
    }
  }

  @parents =
    sort { $a->{rel_type_name} cmp $b->{rel_type_name}
             ||
           $a->{detail} cmp $b->{detail} } @parents;

  return join ",", map { $_->{rel_type_name} . "(" . $_->{detail} . ")" } @parents
}

1;
