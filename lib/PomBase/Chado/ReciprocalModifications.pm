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

has mod_to_mf_mapping => (is => 'rw', init_arg => undef);
has mf_to_mod_mapping => (is => 'rw', init_arg => undef);

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

  open my $mapping_file_fh, '<', $mapping_file
    or die "can't open $mapping_file: $!\n";

  my $header = <$mapping_file_fh>;

  my %mod_to_mf_mapping = ();
  my %mf_to_mod_mapping = ();

  while (defined (my $line = <$mapping_file_fh>)) {
    chomp $line;

    my ($mod_id, $mod_name, $extension_name, $mf_name,
        $mf_id) = split "\t", $line;

    if (!$mod_name || !$mf_name || $mod_name eq '?' || $mf_name eq '?') {
      next;
    }

    my %mapping_conf = (
      mod_name => $mod_name,
      mod_id => $mod_id,
      extension_name => $extension_name,
      mf_name => $mf_name,
      mf_id => $mf_id,
    );

    $mf_to_mod_mapping{$mf_name} = \%mapping_conf;
    $mod_to_mf_mapping{$mod_name} = \%mapping_conf;
  }

  $self->mf_to_mod_mapping(\%mf_to_mod_mapping);
  $self->mod_to_mf_mapping(\%mod_to_mf_mapping);
}

sub check_activity {
  my $self = shift;
  my $act_parent_term_name = shift =~ s/'/''/gr;
  my $mod_parent_term_name = shift =~ s/'/''/gr;
  my $conf = shift;

  my $chado = $self->chado();
  my $dbh = $chado->storage()->dbh();

  my $db_name = $self->config()->{database_name};

  my $missing_mod = 0;
  my $missing_act = 0;

  my $sql = <<"EOQ";
SELECT feature_cvterm_id
FROM pombase_feature_cvterm_ext_resolved_terms fc
WHERE cvterm_name like '%[%'
  AND (base_cvterm_name = '$act_parent_term_name'
  OR base_cvterm_id IN
    (SELECT subject_id FROM cvtermpath WHERE object_id IN
         (SELECT cvterm_id FROM cvterm
          WHERE (name = '$act_parent_term_name'))
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
    }
  }

  $sql = <<"EOQ";
SELECT feature_cvterm_id
FROM pombase_feature_cvterm_ext_resolved_terms fc
WHERE cvterm_name like '%[%'
  AND (base_cvterm_name = '$mod_parent_term_name'
  OR base_cvterm_id IN
    (SELECT subject_id FROM cvtermpath WHERE object_id IN
         (SELECT cvterm_id FROM cvterm
          WHERE (name = '$act_parent_term_name'))
       AND type_id IN (SELECT cvterm_id FROM cvterm WHERE name = 'is_a')
       AND pathdistance > 0))

-- AND fc.pub_id IN (SELECT pub_id FROM pub WHERE uniquename = 'PMID:23770679' OR uniquename = 'PMID:18057023' OR uniquename = 'PMID:21540296')


ORDER BY cvterm_name
EOQ

  $feature_cvterm_rs = $chado->resultset('Sequence::FeatureCvterm')
    ->search({ feature_cvterm_id => { -in => \$sql },
             },
             { join => { cvterm => 'cv' },
               prefetch => ['feature', 'pub'],
             });

  my %mod_genes_and_ext = ();

  while (defined (my $fc = $feature_cvterm_rs->next())) {
    my ($ext_parts, $parent_cvterm) = $self->get_ext_parts($fc);

    my $feature_uniquename =
      $fc->feature()->uniquename() =~ s/\.\d$//r;
    my $pub_uniquename = $fc->pub()->uniquename();

    for my $ext_part (@$ext_parts) {
      if ($ext_part->{rel_type_name} eq $conf->{extension_name}) {
        my $ext_name = $ext_part->{detail} =~ s/^$db_name://r;
        my $key = "$pub_uniquename-$feature_uniquename-$ext_name-" .
          $ext_part->{rel_type_name};

        $mod_genes_and_ext{$key} = 1;
      }
    }
  }

  for my $key (keys %activity_genes_and_targets) {
    my ($pub, $activity_gene, $target) = split /-/, $key;

    my $ext_name = $conf->{extension_name};
    my $mod_key = "$pub-$target-$activity_gene-$ext_name";

    if (defined $mod_genes_and_ext{$mod_key}) {
#      print "found modification: $pub $target $ext_name($activity_gene)\n";
    } else {
      $missing_mod++;
      print "missing modification: $pub $target $ext_name($activity_gene)\n";
    }
  }

  for my $key (keys %mod_genes_and_ext) {
    my ($pub, $mod_gene, $ext_name) = split /-/, $key;

    my $act_key = "$pub-$ext_name-$mod_gene";

    if (defined $activity_genes_and_targets{$act_key}) {
#      print "found activity: $pub $ext_name modifies($mod_gene)\n";
    } else {
      $missing_act++;
      print "missing activity: $pub $ext_name modifies($mod_gene)\n";
    }
  }

  return ($missing_act, $missing_mod);
}

sub process {
  my $self = shift;

  for my $activity_parent_term_name (keys %{$self->mf_to_mod_mapping()}) {
    my $conf = $self->mf_to_mod_mapping()->{$activity_parent_term_name};
    my $mod_parent_term_name = $conf->{mod_name};

    my $ext_name = $conf->{extension_name};

    print qq|checking "$activity_parent_term_name $ext_name" vs "$mod_parent_term_name"\n|;

    my ($missing_act, $missing_mod) =
      $self->check_activity($activity_parent_term_name, $mod_parent_term_name, $conf);

    if ($missing_act == 0 && $missing_mod == 0) {
      print "no missing activities or modifications\n";
    }

    print "\n";
  }
}

1;
