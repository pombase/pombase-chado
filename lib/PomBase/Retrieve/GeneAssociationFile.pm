package PomBase::Retrieve::GeneAssociationFile;

=head1 NAME

PomBase::Retrieve::GeneAssociationFile - Retrieve GO annotation from
           Chado and generate a GAF format file

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::GeneAssociationFile

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

use List::Gen 'iterate';

with 'PomBase::Retriever';

method retrieve() {
  my $chado = $self->chado();

  my $it = do {
    my $cv_rs =
      $chado->resultset('Cv::Cv')->search([
        {
          'me.name' => 'biological_process'
        },
        {
          'me.name' => 'cellular_component'
        },
        {
          'me.name' => 'molecular_function'
        }]);

    my $cvterm_rs =
      $chado->resultset('Cv::Cvterm')->search({
        cv_id => { -in => $cv_rs->get_column('cv_id')->as_query() } });

    my $results =
      $chado->resultset('Sequence::FeatureCvterm')->search({
        cvterm_id => { -in => $cvterm_rs->get_column('cvterm_id')->as_query() } });

    iterate {
      my $row = $results->next();

      if (defined $row) {
        my $cvterm = $row->cvterm();
        my $dbxref = $cvterm->dbxref();
        my $id = $dbxref->db()->name() . ':' . $dbxref->accession();
        return [$cvterm->name(), $id];
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
  return (join "\t", @$res) . "\n";
}
