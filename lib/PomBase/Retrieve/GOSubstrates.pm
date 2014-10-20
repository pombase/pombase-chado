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

use perl5i::2;
use Moose;

use List::Gen 'iterate';

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';

method retrieve() {
  my $chado = $self->chado();

  my $db_name = $self->config()->{database_name};

  if (!defined $db_name) {
    die qq(For GAF export the "database_name" option must be set in the ) .
      "configuration file\n";
  }

  my $sql = q|select f.uniquename, ext_p.value, pub.uniquename from feature f
join feature_cvterm fc on f.feature_id = fc.feature_id
join pub on fc.pub_id = pub.pub_id
join cvterm ext_term on ext_term.cvterm_id = fc.cvterm_id
join cv ext_term_cv on ext_term_cv.cv_id = ext_term.cv_id
join cvtermprop ext_p on ext_term.cvterm_id = ext_p.cvterm_id
join cvterm ext_p_type on ext_p.type_id = ext_p_type.cvterm_id
where ext_term_cv.name = 'PomBase annotation extension terms'
and ext_p_type.name = 'annotation_extension_relation-has_direct_input'
and f.organism_id = | . $self->organism()->organism_id();

  my $dbh = $chado->storage()->dbh();

  my $it = do {

    my $sth = $dbh->prepare($sql);
    $sth->execute()
      or die "Couldn't execute query: " . $sth->errstr();

    iterate {
      my @data = $sth->fetchrow_array();
      if (@data) {
        # this is a hack - turn transcript IDs in gene IDs
        $data[0] =~ s/\.\d$//;
        return [@data];
      } else {
        return undef;
      }
    };
  };
}

method header
{
  return '';
}

method format_result($res)
{
  return (join "\t", @$res);
}


1;
