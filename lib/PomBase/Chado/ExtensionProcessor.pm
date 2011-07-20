package PomBase::Chado::ExtensionProcessor;

=head1 NAME

PomBase::Chado::ExtensionProcessor - Code for processing annotation extensions

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::ExtensionProcessor

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

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
# with 'PomBase::Role::FeatureDumper';
# with 'PomBase::Role::XrefStorer';
# with 'PomBase::Role::ChadoObj';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
# with 'PomBase::Role::FeatureFinder';
# with 'PomBase::Role::OrganismFinder';
# with 'PomBase::Role::QualifierSplitter';
with 'PomBase::Role::ChadoObj';
with 'PomBase::Role::CvtermRelationshipStorer';

has verbose => (is => 'ro');

method store_extension($feature_cvterm, $extensions)
{
  my $extension_cv_name = 'PomBase annotation extension terms';
  my $old_cvterm = $feature_cvterm->cvterm();

  my $new_name = $old_cvterm->name();

  for my $extension (@$extensions) {
    $new_name .=  ' ' . $extension->{relation}->name() .
      ' ' . $extension->{go_term}->name() . ' (PomBase)';
  }

  my $new_term = $self->get_cvterm($extension_cv_name, $new_name);

  if (!defined $new_term) {
    $new_term = $self->find_or_create_cvterm($extension_cv_name, $new_name);

    my $isa_cvterm = $self->get_cvterm('relationship', 'is_a');
    $self->store_cvterm_rel($new_term, $old_cvterm, $isa_cvterm);

    for my $extension (@$extensions) {
      my $rel = $extension->{relation};
      my $go_term = $extension->{go_term};

      warn qq'storing new cvterm_relationship of type "' . $rel->name() .
        " subject: " . $new_term->name() .
        " object: " . $go_term->name() . "\n" if $self->verbose();
      $self->store_cvterm_rel($new_term, $go_term, $rel);
    }
  }

  warn 'storing feature_cvterm from ' .
    $feature_cvterm->feature()->uniquename() . ' to ' .
    $new_term->name() . "\n" if $self->verbose();
  $feature_cvterm->cvterm($new_term);

  $feature_cvterm->update();
}

# $qualifier_data - an array ref of qualifiers
method process($featurecvterm, $qualifier_data, $target_is, $target_of)
{
  my $relationship_cv_name = 'PomBase annotation extension relationships';

  my $feature_uniquename = $featurecvterm->feature()->uniquename();

  warn "processing annotation extension for $feature_uniquename <-> ",
    $featurecvterm->cvterm()->name(), "\n" if $self->verbose();

  for my $qualifiers (@$qualifier_data) {
    my @extension_qualifiers =
      split /\||,/, $qualifiers->{annotation_extension};
    my @extensions = map {
      if (/^(\w+)\((GO:\d+)\)/) {
        my $rel_name = $1;
        my $relation =
          $self->find_cvterm_by_name($relationship_cv_name, $rel_name);
        if (!defined $relation) {
          die "can't find relation cvterm for: $rel_name";
        }

        my $term_id = $2;
        my $go_term = $self->find_cvterm_by_term_id($term_id);
        if (!defined $go_term) {
          die "can't find GO term: $term_id";
        }

        {
          relation => $relation,
          go_term => $go_term,
        }
      } else {
        warn "annotation extension qualifier on $feature_uniquename not understood: $_\n";
        return;
      }
    } @extension_qualifiers;

    $self->store_extension($featurecvterm, \@extensions);
  }
}

1;
