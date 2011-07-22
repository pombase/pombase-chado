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
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::CvtermpropStorer';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::ChadoObj';
with 'PomBase::Role::CvtermRelationshipStorer';

has verbose => (is => 'ro');

method store_extension($feature_cvterm, $extensions)
{
  my $extension_cv_name = 'PomBase annotation extension terms';
  my $old_cvterm = $feature_cvterm->cvterm();

  my $new_name = $old_cvterm->name();

  my $relationship_cv_name = 'PomBase annotation extension relationships';

  for my $extension (@$extensions) {
    my $rel_name = $extension->{rel_name};

    $new_name .=  ' [' . $rel_name . '] ';

    if ($extension->{term}) {
      $new_name .= $extension->{term}->name();
    } else {
      $new_name .= $extension->{identifier};
    }
  }

  my $new_term = $self->get_cvterm($extension_cv_name, $new_name);

  if (!defined $new_term) {
    $new_term = $self->find_or_create_cvterm($extension_cv_name, $new_name);

    my $isa_cvterm = $self->get_cvterm('relationship', 'is_a');
    $self->store_cvterm_rel($new_term, $old_cvterm, $isa_cvterm);

    for my $extension (@$extensions) {
      my $rel_name = $extension->{rel_name};
      my $term = $extension->{term};

      if (defined $term) {
        my $rel = $self->find_cvterm_by_name($relationship_cv_name, $rel_name);

        if (!defined $rel) {
          die "can't find relation cvterm for: $rel_name\n";
        }

        warn qq'storing new cvterm_relationship of type "' . $rel->name() .
          " subject: " . $new_term->name() .
          " object: " . $term->name() . "\n" if $self->verbose();
        $self->store_cvterm_rel($new_term, $term, $rel);
      } else {
        my $identifier = $extension->{identifier};
        if ($rel_name eq 'localization_target_is') {
          $rel_name = 'localization_target';
        }

        $self->store_cvtermprop($new_term,
                                'annotation_extension_relation-' . $rel_name,
                                $identifier);
      }
    }
  }

  warn 'storing feature_cvterm from ' .
    $feature_cvterm->feature()->uniquename() . ' to ' .
    $new_term->name() . "\n" if $self->verbose();
  $feature_cvterm->cvterm($new_term);

  $feature_cvterm->update();
}

# $qualifier_data - an array ref of qualifiers
method process($featurecvterm, $qualifiers, $target_is, $target_of)
{
  my $feature_uniquename = $featurecvterm->feature()->uniquename();

  warn "processing annotation extension for $feature_uniquename <-> ",
    $featurecvterm->cvterm()->name(), "\n" if $self->verbose();

  my @extension_qualifiers =
    split /(?<=\))\||,/, $qualifiers->{annotation_extension};

  my @extensions = map {
    if (/^(\w+)\(([^\)]+)\)$/) {
      my $rel_name = $1;
      my $detail = $2;

      map {
        my $identifier = $_;
        my $term_id = undef;
        my $term = undef;
        if ($identifier =~ /^\w+:\d+$/) {
          $term_id = $identifier;
          $term = $self->find_cvterm_by_term_id($term_id);
          if (!defined $term) {
            die "can't find term with ID: $term_id\n";
          }
        } else {
          if ($identifier =~ /^GeneDB_Spombe:([\w\d\.\-]+)/i) {
            $identifier = $1;
          } else {
            if ($identifier =~ /^(Pfam:PF\d+)$/) {
              $identifier = $1;
            } else {
              warn "can't parse identifier: $identifier\n";
              ();
            }
          }
        }

        {
          rel_name => $rel_name,
          term => $term,
          term_id => $term_id,
          identifier => $identifier
        }
      } split /\|/, $detail;
    } else {
      warn "annotation extension qualifier on $feature_uniquename not understood: $_\n";
      ();
    }
  } @extension_qualifiers;

  if (@extensions) {
    $self->store_extension($featurecvterm, \@extensions);
  }
}

1;
