package PomBase::Chado::ChangeTerms;

=head1 NAME

PomBase::Chado::ChangeTerms - Replace terms in annotations based on a mapping
                              file

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::ChangeTerms

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::CvQuery';

has options => (is => 'ro', isa => 'ArrayRef');
has termid_map => (is => 'rw', init_arg => undef);

method BUILD
{
  my $mapping_file = undef;

  my @opt_config = ('mapping-file=s' => \$mapping_file,);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $mapping_file) {
    die "no --mapping-file argument\n";
  }

  my %termid_map = ();

  open my $mapping_fh, '<', $mapping_file or
    die "can't open mapping file, $mapping_file: $!\n";

  while (defined (my $line = <$mapping_fh>)) {
    $line =~ s/!.*//;
    $line = $line->trim();

    if ($line =~ /^(\w+:\d+)\s+(\w+:\d+)/) {
      my $from_termid = $1;
      my $to_termid = $2;

      next if ($from_termid eq $to_termid);

      $termid_map{$from_termid} = $to_termid;
    }
  }

  $self->termid_map(\%termid_map);

  close $mapping_fh or die "can't close mapping_file: $!\n";
}

method process()
{
  my $chado = $self->chado();
  my $config = $self->config();

  my $proc = sub {
    my $dbh = $chado->storage()->dbh();

    my $temp_table_name = "pombase_change_terms_temp";

    $dbh->do("CREATE TEMPORARY TABLE $temp_table_name(" .
             "from_cvterm_id INTEGER, " .
             "to_cvterm_id INTEGER)");
    $dbh->do("CREATE UNIQUE INDEX ${temp_table_name}_from_idx ON " .
             "$temp_table_name(to_cvterm_id)");

    for my $from_termid (keys %{$self->termid_map()}) {
      my $from_cvterm = $self->find_cvterm_by_term_id($from_termid);
      my $to_cvterm = $self->find_cvterm_by_term_id($self->termid_map()->{$from_termid});

      my $from_cvterm_id = $from_cvterm->cvterm_id();
      my $to_cvterm_id = $to_cvterm->cvterm_id();

      $dbh->do("INSERT INTO $temp_table_name(from_cvterm_id, to_cvterm_id) " .
               "VALUES ($from_cvterm_id, $to_cvterm_id)");
    }

    $dbh->do("update feature_cvterm set cvterm_id = " .
             " (select to_cvterm_id from pombase_change_terms_temp " .
             "   where cvterm_id = from_cvterm_id) " .
             " where cvterm_id in " .
             "   (select from_cvterm_id from pombase_change_terms_temp)");

# OR:
# update feature_cvterm set cvterm_id = to_cvterm_id from
# feature_cvterm fc inner join pombase_change_terms_temp on
# from_cvterm_id = fc.cvterm_id

  };

  $chado->txn_do($proc);
}

1;
