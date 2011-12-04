package PomBase::Retrieve::Ontology;

=head1 NAME

PomBase::Retrieve::Ontology - Retrieve and format ontology data
                              for output

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::Ontology

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2011 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

use List::Gen 'iterate';

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Retriever';
with 'PomBase::Role::CvQuery';

has options => (is => 'ro', isa => 'ArrayRef');

method BUILD
{
  my $chado = $self->chado();

  my $dbh = $self->chado()->storage()->dbh();

  my $constraint_type = undef;
  my $constraint_value = undef;

  my @opt_config = ('constraint-type=s' => \$constraint_type,
                    'constraint-value=s' => \$constraint_value);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $constraint_value) {
    die "no --constraint-value argument\n";
  }

  my $name_constraint;

  if (defined $constraint_type) {
    if ($constraint_type eq 'db_name') {
      $name_constraint = 'db.name = ?';
    } else {
      if ($constraint_type eq 'cv_name') {
        $name_constraint = 'cv.name = ?';
      } else {
        die "unknown --constraint-type argument"
      }
    }
  } else {
    die "no --constraint-type argument\n";
  }

  $self->{_name_constraint} = $name_constraint;
  $self->{_constraint_value} = $constraint_value;
}

method retrieve() {
  my $chado = $self->chado();

  my $dbh = $self->chado()->storage()->dbh();

  my $name_constraint =  $self->{_name_constraint};
  my $constraint_value =  $self->{_constraint_value};

  my $query = "
SELECT t.name, cv.name, db.name, x.accession
  FROM cvterm t, cv, dbxref x, db
 WHERE
   t.cv_id = cv.cv_id AND t.dbxref_id = x.dbxref_id AND
   x.db_id = db.db_id AND $name_constraint
";

  my $it = do {
    my $sth = $dbh->prepare($query);
    $sth->execute($constraint_value)
      or die "Couldn't execute: " . $sth->errstr;

    iterate {
      my @data = $sth->fetchrow_array();

      if (@data) {
        return [@data];
      } else {
        return undef;
      }
    };
  };
}

method header
{
  return <<"EOF";
format-version: 1.2
ontology: pombase
default-namespace: pombase
EOF
}

method format_result($data)
{
  my $id = $data->[2] . ':' . $data->[3];
  my $name = $data->[0];
  my $namespace = $data->[1];
  return <<"EOF";
[Term]
id: $id
name: $name
namespace: $namespace

EOF
}
