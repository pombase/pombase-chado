package PomBase::Check::PhenotypesNotInCategory;

=head1 NAME

PomBase::Check::PhenotypesNotInCategory - Find phenotypes terms that don't have
      a parent in one of the "split_by_parents" categories in the website
      configuration for fission_yeast_phenotype

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Check::PhenotypesNotInCategory

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

sub description {
  my $self = shift;

  return "Check that all phenotype terms have a parent in one of the categories " .
    "in the website configuration for fission_yeast_phenotype";
}

with 'PomBase::Checker';

sub check {
  my $self = shift;

  my $chado = $self->chado();

  my $fypo_config = $self->website_config()->{cv_config}->{fission_yeast_phenotype};

  my @split_by_parents = @{$fypo_config->{split_by_parents}};

  my @parents_termids =
    map {
      my $split_conf = $_;

      @{$split_conf->{termids}};
    } @split_by_parents;

  my $place_holders = join ",", ("?") x @parents_termids;

  my $query = <<"EOQ";
    SELECT
       db.name || ':' || x.accession as termid,
       pub.uniquename,
       fc.cvterm_name,
       count(fc.feature_cvterm_id)
FROM pombase_feature_cvterm_ext_resolved_terms fc
JOIN cvterm t on t.cvterm_id = fc.base_cvterm_id
JOIN pub ON pub.pub_id = fc.pub_id
JOIN dbxref x on x.dbxref_id = t.dbxref_id
JOIN db ON db.db_id = x.db_id
WHERE base_cv_name = 'fission_yeast_phenotype'
  AND base_cvterm_id NOT IN
    (SELECT subject_id
     FROM cvtermpath
     WHERE object_id IN
         (SELECT cvterm_id
          FROM cvterm
          WHERE dbxref_id IN
              (SELECT dbxref_id
               FROM dbxref x
               JOIN db ON db.db_id = x.db_id
               WHERE db.name || ':' || x.accession in
                   ($place_holders))))
GROUP BY pub.uniquename,
         fc.cvterm_name,
         termid
ORDER BY fc.cvterm_name, pub.uniquename;
EOQ

  my $dbh = $chado->storage()->dbh();
  my $sth = $dbh->prepare($query);
  $sth->execute(@parents_termids) or die "Couldn't execute: " . $sth->errstr;

  my $output_text = '';
  my $count = 0;

  while (my @data = map { $_ // '[null]' } $sth->fetchrow_array()) {
    $output_text .= ("  " . (join "\t", @data));
    $output_text .= "\n";
    $count++;
  }

  $self->output_text($output_text);

  return $count == 0;
}

1;
