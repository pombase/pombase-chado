package PomBase::Chado::RemoveDuplicateInteractions;

=head1 NAME

PomBase::Chado::RemoveDuplicateInteractions - Remove old style gene-gene
   interactions that have a corresponding genotype-genotype interaction

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::RemoveDuplicateInteractions

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2026 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ExtensionDisplayer';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has symmetrical_interaction_evidence_codes => (is => 'rw', init_arg => undef,
                                               lazy_build => 1);
has interactions_from_genotypes => (is => 'rw', init_arg => undef);

sub _build_symmetrical_interaction_evidence_codes {
  my $self = shift;

  my @symmetrical_ev_codes = ();

  my %evidence_types = %{$self->config()->{evidence_types}};

  map {
    my $ev_name = $_;

    my $symmetrical = $evidence_types{$ev_name}->{symmetrical};

    if ($symmetrical && lc $symmetrical ne 'no') {
      push @symmetrical_ev_codes, $ev_name;
    }
  } keys %evidence_types;

  return [@symmetrical_ev_codes];
}

sub BUILD {
  my $self = shift;

  my %interactions_from_genotypes = ();

  my $genotype_interaction_rs =
    $self->chado()->resultset('Sequence::Feature')
    ->search({
      'type.name' => 'genotype_interaction',
      'type_2.name' => 'interaction_type',
    }, {
      join => [ 'type', { featureprops => 'type', feature_pubs => 'pub' } ],
    });

  while (defined (my $interaction = $genotype_interaction_rs->next())) {
    my $subj_rel_rs = $interaction
      ->feature_relationship_objects({ 'type.name' => 'interaction_double_mutant_genotype',
                                     },
                                     { join => ['type'] });
    my $interaction_type = $interaction->featureprops()->first()->value();
    my $pub_uniquename = $interaction->feature_pubs()->first()->pub()->uniquename();

    for my $subj_rel ($subj_rel_rs->all()) {
      my $double_mutant = $subj_rel->subject();

      my @gene_uniquenames = ();

      for my $allele_rel ($double_mutant->feature_relationship_objects()->all()) {
        my $allele = $allele_rel->subject();

        my $gene_rel_rs = $allele->feature_relationship_subjects()
          ->search({ 'type.name' => 'instance_of' }, { join => 'type' });

        for my $gene_rel ($gene_rel_rs->all()) {
          my $gene = $gene_rel->object();
          my $gene_uniquename = $gene->uniquename();
          if (!grep(/^$gene_uniquename$/, @gene_uniquenames)) {
            push @gene_uniquenames, $gene->uniquename();
          }
        }
      }

      my $gene_uniquename_a = $gene_uniquenames[0];
      my $gene_uniquename_b = $gene_uniquenames[1] // $gene_uniquenames[0];

      my $key = "$pub_uniquename-$gene_uniquename_a-$interaction_type-$gene_uniquename_b";
      $interactions_from_genotypes{$key} = {
        pub_uniquename => $pub_uniquename,
        interactor_a => $gene_uniquename_a,
        interaction_type => $interaction_type,
        interactor_b => $gene_uniquename_b,
      };

      if (grep { $_ eq $interaction_type } @{$self->symmetrical_interaction_evidence_codes()}) {
        my $rev_key = "$pub_uniquename-$gene_uniquename_b-$interaction_type-$gene_uniquename_a";
        $interactions_from_genotypes{$rev_key} = {
          pub_uniquename => $pub_uniquename,
          interactor_a => $gene_uniquename_a,
          interaction_type => $interaction_type,
          interactor_b => $gene_uniquename_b,
        };
      }
    }
  }

  $self->interactions_from_genotypes(\%interactions_from_genotypes);
}

sub process {
  my $self = shift;

  my $guard = $self->chado()->txn_scope_guard();

  my $interaction_rs =
    $self->chado()->resultset('Sequence::FeatureRelationship')
    ->search({
      'type.name' => 'interacts_genetically',
      'type_2.name' => 'evidence',
    }, {
      join => [ 'type', 'subject', 'object',
                { feature_relationshipprops => 'type' },
                { feature_relationship_pubs => 'pub' } ],
    });

  while (defined (my $interaction = $interaction_rs->next())) {
    my $interactor_a = $interaction->subject()->uniquename();
    my $interactor_a_name = $interaction->subject()->name();
    my $interactor_b = $interaction->object()->uniquename();
    my $interactor_b_name = $interaction->object()->name();

    my $interaction_type = $interaction->feature_relationshipprops()
      ->search({ 'type.name' => 'evidence' },
               { join => 'type' })
      ->first()
      ->value();

    my $pub_uniquename = $interaction->feature_relationship_pubs->first()->pub()->uniquename();

    my $key = "$pub_uniquename-$interactor_a-$interaction_type-$interactor_b";

    my $result = $self->interactions_from_genotypes()->{$key};

    if ($result) {
      $interaction->delete();
    }
  }

  $guard->commit();
}

1;
