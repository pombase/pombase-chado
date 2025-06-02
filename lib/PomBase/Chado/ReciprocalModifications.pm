package PomBase::Chado::ReciprocalModifications;

=head1 NAME

PomBase::Chado::ReciprocalModifications - Warn about missing reciprocal
  annotations for modifications

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::ReciprocalModifications

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

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

has mapping_file => (is => 'rw', init_arg => undef);

sub BUILD {
  my $self = shift;

  my $mapping_file = undef;

  my @opt_config = ('mapping-file=s' => \$mapping_file);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!$mapping_file) {
    die "missing argument: --mapping-file\n";
  }


}

sub check_activity {
  my $self = shift;
  my $act_parent_term_name = shift;
  my $mod_parent_term_name = shift;

  my $chado = $self->chado();
  my $dbh = $chado->storage()->dbh();

  my $db_name = $self->config()->{database_name};

  my $sql = <<"EOQ";
SELECT feature_cvterm_id
FROM pombase_feature_cvterm_ext_resolved_terms fc
WHERE cvterm_name like '%[%'
  AND (base_cvterm_name = '$act_parent_term_name'
  OR base_cvterm_name = '$mod_parent_term_name'
  OR base_cvterm_id IN
    (SELECT subject_id FROM cvtermpath WHERE object_id IN
         (SELECT cvterm_id FROM cvterm
          WHERE (name = '$act_parent_term_name' OR name = '$mod_parent_term_name'))
       AND type_id IN (SELECT cvterm_id FROM cvterm WHERE name = 'is_a')
       AND pathdistance > 0))

-- AND fc.pub_id IN (SELECT pub_id FROM pub WHERE uniquename = 'PMID:23770679' OR uniquename = 'PMID:18057023' OR uniquename = 'PMID:21540296')


ORDER BY cvterm_name
EOQ

  my $feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm')
    ->search({ feature_cvterm_id => { -in => \$sql },
             },
             { join => { cvterm => 'cv' },
               prefetch => ['feature', 'pub'],
             });

  my %activity_genes_and_targets = ();
  my %mod_genes_and_added_by = ();

  while (defined (my $fc = $feature_cvterm_rs->next())) {
    my ($ext_parts, $parent_cvterm) = $self->get_ext_parts($fc);

    my $feature_uniquename =
      $fc->feature()->uniquename() =~ s/\.\d$//r;
    my $pub_uniquename = $fc->pub()->uniquename();

    for my $ext_part (@$ext_parts) {
      if ($ext_part->{rel_type_name} eq 'has_input') {
        my $target = $ext_part->{detail} =~ s/^$db_name://r;
        my $key = "$pub_uniquename-$feature_uniquename-$target";
        $activity_genes_and_targets{$key} = 1;
      }

      if ($ext_part->{rel_type_name} eq 'added_by') {
        my $added_by = $ext_part->{detail} =~ s/^$db_name://r;
        my $key = "$pub_uniquename-$feature_uniquename-$added_by";

        $mod_genes_and_added_by{$key} = 1;
      }
    }
  }

  for my $key (keys %activity_genes_and_targets) {
    my ($pub, $activity_gene, $target) = split /-/, $key;

    my $mod_key = "$pub-$target-$activity_gene";

    if (defined $mod_genes_and_added_by{$mod_key}) {
#      print "found modification: $target added_by($activity_gene)\n";
    } else {
      print "missing modification: $pub $target added_by($activity_gene)\n";
    }
  }

  for my $key (keys %mod_genes_and_added_by) {
    my ($pub, $mod_gene, $added_by) = split /-/, $key;

    my $act_key = "$pub-$added_by-$mod_gene";

    if (defined $activity_genes_and_targets{$act_key}) {
#      print "found activity: $pub $added_by modifies($mod_gene)\n";
    } else {
      print "missing activity: $pub $added_by modifies($mod_gene)\n";
    }
  }

  return 1
}

sub process {
  my $self = shift;

  my $activity_parent_term_name = "protein kinase activity";
  my $mod_parent_term_name = "phosphorylated residue";

  $self->check_activity($activity_parent_term_name, $mod_parent_term_name);

  return 1;
}

1;
