package PomBase::Chado::InitUtil;

=head1 NAME

PomBase::Load - Code for initialising and loading data into the PomBase Chado
                database

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Load

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

use Carp;

use PomBase::Chado::LoadOrganism;

use YAML::Any qw(DumpFile LoadFile);

sub _fix_annotation_extension_rels {
  my $chado = shift;
  my $config = shift;

   my @extension_rel_terms = map {
     ($chado->resultset('Cv::Cv')->search({ 'me.name' => $_ })
        ->search_related('cvterms')
        ->search({ is_relationshiptype => 1, is_obsolete => 0 })->all());
   } @{$config->{extension_relation_cv_names}};

  push @{$config->{cvs}->{cvterm_property_type}},
    map {
      'annotation_extension_relation-' . $_->name();
    } @extension_rel_terms;
}

sub _load_cvterms {
  my $chado = shift;
  my $config = shift;
  my $test_mode = shift;

  my $db_name = 'PBO';
  my $db = $chado->resultset('General::Db')->find({ name => $db_name });

  my %cv_confs = %{$config->{cvs}};

  my %cvs = ();

  for my $cv_name (keys %cv_confs) {
    my $cv;

    if (exists $cvs{$cv_name}) {
      $cv = $cvs{$cv_name};
    } else {
      $cv = $chado->resultset('Cv::Cv')->find_or_create({ name => $cv_name });
      $cvs{$cv_name} = $cv;
    }

    my @cvterm_confs = @{$cv_confs{$cv_name}};

    for my $cvterm_conf (@cvterm_confs) {
      my $cvterm_name;
      my $cvterm_definition;

      if (ref $cvterm_conf) {
        $cvterm_name = $cvterm_conf->{name};
        $cvterm_definition = $cvterm_conf->{definition};
      } else {
        $cvterm_name = $cvterm_conf;
      }

      if ($cv_name ne 'PomBase gene characterisation status') {
        $cvterm_name =~ s/ /_/g;
      }

      my $cvterm =
        $chado->resultset('Cv::Cvterm')
          ->find({ name => $cvterm_name,
                   cv_id => $cv->cv_id(),
                   is_obsolete => 0,
                 });

      if (!defined $cvterm) {
        my $accession = $config->{id_counter}->get_dbxref_id($db_name);
        my $formatted_accession = sprintf "%07d", $accession;

        my $dbxref =
          $chado->resultset('General::Dbxref')->find_or_create({
            db_id => $db->db_id(),
            accession => $formatted_accession,
          });

        $chado->resultset('Cv::Cvterm')
          ->create({ name => $cvterm_name,
                     cv_id => $cv->cv_id(),
                     dbxref_id => $dbxref->dbxref_id(),
                     definition => $cvterm_definition,
                     is_obsolete => 0,
                   });
      }
    }
  }
}

sub _load_cv_defs {
  my $chado = shift;
  my $config = shift;

  my $db_name = 'PomBase';

  my %cv_defs = %{$config->{cv_definitions}};

  for my $cv_name (keys %cv_defs) {
    my $cv = $chado->resultset('Cv::Cv')->find({ name => $cv_name });

    if (defined $cv) {
      $cv->definition($cv_defs{$cv_name});
      $cv->update();
    } else {
      die "can't set definition for $cv_name as it doesn't exist\n";
    }
  }
}

sub _load_dbs {
  my $chado = shift;
  my $config = shift;

  my @dbs = @{$config->{dbs}};

  for my $db (@dbs) {
    $chado->resultset('General::Db')->find_or_create({ name => $db });
  }
}

sub init_objects {
  my $chado = shift;
  my $config = shift;

  _fix_annotation_extension_rels($chado, $config);
  _load_cvterms($chado, $config, $config->{test});
  _load_cv_defs($chado, $config);
  _load_dbs($chado, $config);
}

1;
