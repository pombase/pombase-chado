package PomBase::Check;

=head1 NAME

PomBase::Check - Code for checking database integrity

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Check

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
use feature qw(switch say);
no if $] >= 5.018, warnings => "experimental::smartmatch";

use open ':encoding(utf8)';

use Module::Find;

use PomBase::Chado;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';

has website_config => (is => 'ro');
has output_prefix => (is => 'ro');

sub _do_query_checks {
  my $self = shift;

  my @query_checks = @{$self->config()->{check_chado}->{query_checks}};

  my $dbh = $self->chado()->storage()->dbh();

  my $seen_failure = 0;

  for my $check (@query_checks) {
    my $name = $check->{name};

    my $output_file = $self->output_prefix() . ".$name";

    open my $out_fh, '>', $output_file
      or die "can't open Chado check output file $output_file: $!\n";

    binmode($out_fh, ":utf8");

    my $query = $check->{query} =~ s/;\s*$//r;
    my $warning_on_failure = $check->{warning_on_failure};

    # if true, show the result set content on failure:
    my $verbose_fail = $check->{verbose_fail} && $check->{verbose_fail} eq 'true';
    my $expected_conf = $check->{expected} //
      die "expected value not set for $name\n";
    my $description = $check->{description} // $name;

    my $count_sth = $dbh->prepare("select count(*) from ($query) as sub");
    $count_sth->execute() or die "Couldn't execute: " . $count_sth->errstr;

    my @data = $count_sth->fetchrow_array();

    die "query ('$query') didn't return exactly one row" if @data != 1;

    my $type = '=';
    my $expected;

    if ($expected_conf =~ /^(>|<|<=|>=)?\s*(\d+)$/) {
      if (defined $1) {
        $type = $1;
      }
      $expected = $2;
    } else {
      die "expected value not understood: $expected_conf\n";
    }

    my $failure;

    given ($type) {
      when ('=') {
        if ($data[0] ne $expected) {
          $failure = " expected $expected but got $data[0]";
        }
      }
      when ('<') {
        if ($data[0] >= $expected) {
          $failure = " expected less than $expected but got $data[0]";
        }
      }
      when ('>') {
        if ($data[0] <= $expected) {
          $failure = " expected greater than $expected but got $data[0]";
        }
      }
      when ('<=') {
        if ($data[0] > $expected) {
          $failure = " expected $type $expected but got $data[0]";
        }
      }
      when ('>=') {
        if ($data[0] < $expected) {
          $failure = " expected $type $expected but got $data[0]";
        }
      }
    }

    if ($failure) {
      if ($warning_on_failure) {
        print $out_fh "$description - WARNING: $failure\n
(this is a warning that won't cause the Chado checks to fail)\n";
      } else {
        print $out_fh "$description - CHECK FAILURE: $failure\n";
        $seen_failure = 1;
      }
      if ($verbose_fail) {
        my $sth = $dbh->prepare($query);
        $sth->execute() or die "Couldn't execute: " . $sth->errstr;

        my @column_names = @{$sth->{NAME}};

        print $out_fh (join "\t", @column_names), "\n";

        while (my @data = map { $_ // '[null]' } $sth->fetchrow_array()) {
          print $out_fh "  " . (join "\t", @data). "\n";
        }
      }
    } else {
      # success
    }

    close $out_fh;
  }

  return $seen_failure;
}

sub run {
  my $self = shift;

  my $seen_failure = 0;

  my @check_modules = usesub PomBase::Check;

  for my $module (@check_modules) {
    warn "Running check: $module\n";
    my $obj = $module->new(config => $self->config(),
                           chado => $self->chado(),
                           website_config => $self->website_config());

    if (!$obj->check()) {
      warn "failed test: ", $obj->description(), "\n";
      $seen_failure = 1;
    }
  }

  return $self->_do_query_checks() || $seen_failure;
}

1;
