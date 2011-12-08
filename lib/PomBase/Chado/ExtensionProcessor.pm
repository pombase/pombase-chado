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
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::ChadoObj';
with 'PomBase::Role::CvtermRelationshipStorer';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';

has verbose => (is => 'ro');

method store_extension($feature_cvterm, $extensions)
{
  my $extension_cv_name = 'PomBase annotation extension terms';
  my $old_cvterm = $feature_cvterm->cvterm();

  my $new_name = $old_cvterm->name();

  my $relationship_cv_name = 'go_annotation_relations';

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

        if ($self->get_cvterm_rel($new_term, $term, $rel)->count() > 0) {
          my $dbxref = $term->dbxref();
          my $accession = $dbxref->db()->name() . ":" . $dbxref->accession();
          die "duplicated annotation extension for ", $rel->name(), " (", $accession, ")\n";
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

method check_targets($target_is_quals, $target_of_quals)
{
  my $organism = $self->find_organism_by_common_name('pombe');

  die unless defined $organism;

  while (my ($target_uniquename, $details) = each(%{$target_of_quals})) {
    for my $detail (@$details) {
      my $gene_name = $detail->{name};

      my $gene1_feature = undef;
      try {
        $gene1_feature = $self->find_chado_feature($gene_name, 1, 1, $organism);
      } catch {
        warn "problem with target annotation of ", $detail->{feature}->uniquename(), ": $_";
      };
      if (!defined $gene1_feature) {
        next;
      }

      my $gene1_uniquename = $gene1_feature->uniquename();

      if (!exists $target_is_quals->{$gene1_uniquename} ||
          !grep {
            my $current = $_;
            my $target_feature;
            try {
              $target_feature = $self->find_chado_feature($current->{name}, 1, 1, $organism);
            } catch {
              warn "problem on gene ", $current->{feature}->uniquename(), ": $_";
            };

            if (defined $target_feature) {
              $target_feature->uniquename() eq $target_uniquename;
            } else {
              0;
            }
          } @{$target_is_quals->{$gene1_uniquename}}) {

        my $name_bit;

        my $target_feature;
        try {
          $target_feature = $self->find_chado_feature($target_uniquename, 1, 1, $organism);
        } catch {
        };

        if (defined $target_feature && defined $target_feature->name()) {
          $name_bit = $target_feature->name();
        } else {
          $name_bit = $target_uniquename;
        }
        warn qq:no "target is $name_bit" in $gene_name ($gene1_uniquename)\n:;
      }
    }
  }
}

method process($post_process_data, $target_is_quals, $target_of_quals)
{
  $self->check_targets($target_is_quals, $target_of_quals);

  while (my ($feature_cvterm_id, $data_list) = each %{$post_process_data}) {
    for my $data (@$data_list) {
      my $feature_cvterm = $data->{feature_cvterm};
      my $qualifiers = $data->{qualifiers};

      try {
        $self->process_one_annotation($feature_cvterm, $qualifiers,
                                      $target_is_quals, $target_of_quals);
      } catch {
        warn "failed to add annotation extension to ",
        $feature_cvterm->feature()->uniquename(), ' <-> ',
        $feature_cvterm->cvterm()->name(), ": $_";
      }
    }
  }

}

# $qualifier_data - an array ref of qualifiers
method process_one_annotation($featurecvterm, $qualifiers,
                              $target_is_quals, $target_of_quals)
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
          if ($identifier =~ /^(PomBase|GeneDB_?Spombe):([\w\d\.\-]+)/i) {
            $identifier = $2;
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
