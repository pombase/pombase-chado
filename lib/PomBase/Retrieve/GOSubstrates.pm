package PomBase::Retrieve::GOSubstrates;

=head1 NAME

PomBase::Retrieve::GOSubstrates - Export the GO extension substrate

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::GOSubstrates

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use Moose;

use Iterator::Simple qw(iterator);

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';

sub retrieve {
  my $self = shift;

  my $chado = $self->chado();

  my $db_name = $self->config()->{database_name};

  if (!defined $db_name) {
    die qq(For GAF export the "database_name" option must be set in the ) .
      "configuration file\n";
  }

  my $sql = q|
SELECT f.uniquename,
       ext_p.value,
       pub.uniquename
FROM feature f
JOIN pombase_feature_cvterm_ext_resolved_terms fc ON f.feature_id = fc.feature_id
JOIN pub ON fc.pub_id = pub.pub_id
JOIN cvterm ext_term ON ext_term.cvterm_id = fc.cvterm_id
JOIN cv ext_term_cv ON ext_term_cv.cv_id = ext_term.cv_id
JOIN cvtermprop ext_p ON ext_term.cvterm_id = ext_p.cvterm_id
JOIN cvterm ext_p_type ON ext_p.type_id = ext_p_type.cvterm_id
WHERE ext_term_cv.name = 'PomBase annotation extension terms'
  AND (ext_p_type.name IN
    ('annotation_extension_relation-directly_negatively_regulates',
     'annotation_extension_relation-directly_positively_regulates')
   OR (ext_p_type.name IN ('annotation_extension_relation-has_regulation_target',
                           'annotation_extension_relation-has_input')
         AND base_cv_name = 'molecular_function'))
  AND f.organism_id = | . $self->organism()->organism_id();

  my $dbh = $chado->storage()->dbh();

  my $it = do {

    my $sth = $dbh->prepare($sql);
    $sth->execute()
      or die "Couldn't execute query: " . $sth->errstr();

    iterator {
      my @data = $sth->fetchrow_array();
      if (@data) {
        # this is a hack - turn transcript IDs in gene IDs
        $data[0] =~ s/\.\d$//;
        # remove DB prefix added by https://github.com/japonicusdb/japonicus-config/issues/30
        $data[1] =~ s/\w+://;
        return [@data];
      } else {
        return undef;
      }
    };
  };
}

sub header {
  my $self = shift;
  return '';
}

sub format_result {
  my $self = shift;
  my $res = shift;

  return (join "\t", @$res);
}


1;
