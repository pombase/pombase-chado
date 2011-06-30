package PomBase::TestUtil;

=head1 NAME

PomBase::TestUtil - Utility methods for testing the PomBase code

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::TestUtil

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
use YAML qw(LoadFile);
use File::Temp qw(tempfile);

use Bio::Chado::Schema;

has test_config => (is => 'rw', init_arg => undef, isa => 'HashRef');
has chado => (is => 'rw', init_arg => undef, isa => 'Bio::Chado::Schema');

my $TEST_CONFIG_FILE = 't/test_config.yaml';

method _make_test_db
{
  my ($fh, $temp_db) = tempfile(UNLINK => 1);
  system "sqlite3 $temp_db < t/chado_schema.sql";
  return Bio::Chado::Schema->connect("dbi:SQLite:$temp_db");
}

method _populate_db($chado)
{
  my $test_data = $self->test_config()->{data};
  my $cv_conf = $test_data->{cv};

  for my $row (@$cv_conf) {
    $chado->resultset("Cv::Cv")->create($row);
  }
}

method BUILD
{
  my ($fh, $temp_db) = tempfile();

  my $test_config = LoadFile($TEST_CONFIG_FILE);
  $self->test_config($test_config);

  my $chado = $self->_make_test_db();
  $self->_populate_db($chado);
  $self->chado($chado);
}

1;
