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

use strict;
use warnings;
use Carp;

use Moose;

use Iterator::Simple qw(iterator);

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';

has options => (is => 'ro', isa => 'ArrayRef');

# if true return stanzas for parent terms of those terms that pass the
# constraint_type filter, even if the parent doesn't pass the filter
has retrieve_parent_terms => (is => 'rw', default => 0, init_arg => undef);

sub BUILD {
  my $self = shift;
  my $chado = $self->chado();

  my $dbh = $self->chado()->storage()->dbh();

  my $constraint_type = undef;
  my $constraint_value = undef;
  my $retrieve_parent_terms = 0;

  my @opt_config = ('constraint-type=s' => \$constraint_type,
                    'constraint-value=s' => \$constraint_value,
                    'retrieve-parent-terms' => \$retrieve_parent_terms);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!defined $constraint_value) {
    die "no --constraint-value argument\n";
  }

  if (lc $retrieve_parent_terms eq 'yes' ||
      lc $retrieve_parent_terms eq 'true' ||
      $retrieve_parent_terms) {
    $retrieve_parent_terms = 1;
  } else {
    $retrieve_parent_terms = 0;
  }

  $self->retrieve_parent_terms($retrieve_parent_terms);

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
  $self->{_parents} = {};
}

sub retrieve {
  my $self = shift;

  my $chado = $self->chado();

  my $dbh = $self->chado()->storage()->dbh();

  my $name_constraint =  $self->{_name_constraint};
  my $constraint_value =  $self->{_constraint_value};

  my $retrieve_parent_terms = $self->retrieve_parent_terms();

  my $query = "
SELECT t.name, cv.name, db.name, x.accession, obj.name, objdb.name, objdbxref.accession
  FROM cv, dbxref x, db, cvterm t
  LEFT OUTER JOIN cvterm_relationship r ON r.subject_id = t.cvterm_id AND
       r.type_id = (select cvterm_id from cvterm, cv where cvterm.cv_id = cv.cv_id and (cv.name = 'relations' OR cv.name = 'autocreated') and cvterm.name = 'is_a')
  LEFT OUTER JOIN cvterm obj ON r.object_id = obj.cvterm_id
  LEFT OUTER JOIN dbxref objdbxref ON objdbxref.dbxref_id = obj.dbxref_id
  LEFT OUTER JOIN db objdb ON objdbxref.db_id = objdb.db_id
 WHERE
   t.cv_id = cv.cv_id AND
   t.dbxref_id = x.dbxref_id AND
   x.db_id = db.db_id AND
   $name_constraint
";

  my $it = do {
    my $sth = $dbh->prepare($query);
    $sth->execute($constraint_value)
      or die "Couldn't execute: " . $sth->errstr;

    iterator {
      my @data = ();

      if (defined $sth) {
        @data = $sth->fetchrow_array();
        if ($retrieve_parent_terms) {
          my $parentname = $data[4];
          if (defined $parentname) {
            my $termid = $data[5] . ':' . $data[6];
            if (!exists $self->{_parents}->{$termid}) {
              my $cvterm = $self->find_cvterm_by_term_id($termid);
              if (defined $cvterm) {
                $self->{_parents}->{$termid} = $cvterm;
              }
            }
          }
        }
      }

      if (@data) {
        return [@data];
      } else {
        $sth = undef;
        if ($retrieve_parent_terms && keys %{$self->{_parents}} > 0) {
          my ($termid, $cvterm) = each %{$self->{_parents}};
          return undef unless defined $termid;
          delete $self->{_parents}->{$termid};
          if (!defined $cvterm) {
            die "no cvterm for $termid\n";
          }
          my $dbxref = $cvterm->dbxref();
          return [$cvterm->name(), $cvterm->cv()->name(),
                  $dbxref->db()->name(), $dbxref->accession()];
        } else {
          return ();
        }
      }
    };
  };
}

sub header {
  my $self = shift;
  return <<"EOF";
format-version: 1.2
ontology: pombase
default-namespace: pombase
EOF
}

sub _parentid {
  my $self = shift;
  my $data = shift;

  my $parentname = $data->[4];
  if (defined $parentname) {
    return $data->[5] . ':' . $data->[6];
  } else {
    return undef;
  }
}

sub format_result {
  my $self = shift;
  my $data = shift;

  my $id = $data->[2] . ':' . $data->[3];
  my $name = $data->[0];
  my $namespace = $data->[1];
  my $isa = '';
  my $parentid = $self->_parentid($data);
  if (defined $parentid) {
    $isa = "\nis_a: $parentid";
  }
  return <<"EOF";
[Term]
id: $id
name: $name
namespace: $namespace$isa

EOF
}

1;
