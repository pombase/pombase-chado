package PomBase::Check::XrefCheck;

=head1 NAME

PomBase::Check::XrefCheck - Check that DB prefixes match the GO xrefs file
      (http://current.geneontology.org/metadata/db-xrefs.yaml)

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Check::XrefCheck

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2024 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;
use Moose;

with 'PomBase::Checker';

sub description {
  return "Check that DB prefixes match the GO xrefs file " .
    "(http://current.geneontology.org/metadata/db-xrefs.yaml)";
}

sub check {
  my $self = shift;

  my $chado = $self->chado();

  my $output_text = '';

  my $query = <<"EOQ";
select with_p.value, array_to_string(array (SELECT sess_p.value FROM feature_cvtermprop sess_p JOIN cvterm sess_pt ON sess_p.type_id = sess_pt.cvterm_id WHERE fc.feature_cvterm_id = sess_p.feature_cvterm_id AND sess_pt.name = 'canto_session'), ','), array_to_string(array (SELECT sess_p.value FROM feature_cvtermprop sess_p JOIN cvterm sess_pt ON sess_p.type_id = sess_pt.cvterm_id WHERE fc.feature_cvterm_id = sess_p.feature_cvterm_id AND sess_pt.name = 'source_file'), ',') from feature_cvterm fc join feature_cvtermprop with_p on fc.feature_cvterm_id = with_p.feature_cvterm_id join cvterm with_p_type on with_p_type.cvterm_id = with_p.type_id where with_p_type.name = 'with';
EOQ

  my $dbh = $chado->storage()->dbh();
  my $sth = $dbh->prepare($query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  while (my ($value, $sessions, $source_file) = $sth->fetchrow_array()) {
    next if !$value;

    if ($value =~ /^(.*?):.*/) {
      my $prefix = $1;
      if (!exists $self->xref_config()->{$prefix}) {
        $output_text .= "$value\t$sessions\t$source_file\n";
      }
    }
  }

  $self->output_text($output_text);

  return 0;
}
