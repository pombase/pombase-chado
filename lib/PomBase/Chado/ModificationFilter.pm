package PomBase::Chado::ModificationFilter;

=head1 NAME

PomBase::Chado::ModificationFilter - Code for removing redundant modifications

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::ModificationFilter

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

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has primary_assigner => (is => 'rw', init_arg => undef);
has secondary_assigner => (is => 'rw', init_arg => undef);
has secondary_assigner_pmid => (is => 'rw', init_arg => undef);

sub BUILD
{
  my $self = shift;

  my $primary_assigner = undef;
  my $secondary_assigner = undef;
  my $secondary_assigner_pmid = undef;

  my @opt_config = ('primary-assigner=s' => \$primary_assigner,
                    'secondary-assigner=s' => \$secondary_assigner,
                    'secondary-assigner-pmid=s' => \$secondary_assigner_pmid,
);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!$primary_assigner) {
    die "missing argument: --primary-assigner\n";
  }

  if (!$secondary_assigner) {
    die "missing argument: --secondary-assigner\n";
  }

  if (!$secondary_assigner_pmid) {
    die "missing argument: --secondary-assigner-pmid\n";
  }

  $self->primary_assigner($primary_assigner);
  $self->secondary_assigner($secondary_assigner);
  $self->secondary_assigner_pmid($secondary_assigner_pmid);
}

sub make_key
{
  return join '-=:=-', @_;
}


=head2 process

 Usage : my $filter = PomBase::Chado::ModificationFilter->new(config => $config,
                                                                  chado => $chado);
         $filter->process();
 Func  : If a modification comes from UniProt and PomBase sources, keep just
         one and write a log of those that are removed
 Args  : $config - a Config object
         $chado - a schema object of the Chado database
 Return: nothing, dies on error

=cut

sub process
{
  my $self = shift;

  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $query = <<'EOQ';
SELECT fc.feature_cvterm_id,
       pub.uniquename AS pmid,
       regexp_replace(f.uniquename, '\.1$', '') AS gene_uniquename,
       fc.base_cvterm_name AS term_name,
  (SELECT value
   FROM feature_cvtermprop p
   WHERE p.feature_cvterm_id = fc.feature_cvterm_id
     AND p.type_id IN
       (SELECT cvterm_id
        FROM cvterm
        WHERE name = 'residue')
    LIMIT 1) as residue,
  (SELECT value
   FROM feature_cvtermprop p
   WHERE p.feature_cvterm_id = fc.feature_cvterm_id
     AND p.type_id IN
       (SELECT cvterm_id
        FROM cvterm
        WHERE name = 'evidence')
   LIMIT 1) AS evidence
FROM pombase_feature_cvterm_ext_resolved_terms fc
JOIN pub ON pub.pub_id = fc.pub_id
JOIN feature f ON f.feature_id = fc.feature_id
JOIN feature_cvtermprop assigned_by_prop ON assigned_by_prop.feature_cvterm_id = fc.feature_cvterm_id
JOIN cvterm assigned_by_prop_type ON assigned_by_prop_type.cvterm_id = assigned_by_prop.type_id
WHERE assigned_by_prop_type.name = 'assigned_by'
  AND assigned_by_prop.value = ?
  AND base_cv_name = 'PSI-MOD'
EOQ

  my $secondary_sth = $dbh->prepare($query);

  $secondary_sth->execute('' . $self->secondary_assigner())
    or die ("Couldn't execute: " . $secondary_sth->errstr);

  my %secondary_assigner_annotations = ();

  while (my ($feature_cvterm_id, $pmid, $gene_uniquename, $term_name, $residue) =
         $secondary_sth->fetchrow_array()) {
    $residue //= '';
    my $key = make_key($gene_uniquename, $term_name, $residue);

    push @{$secondary_assigner_annotations{$key}->{$pmid}}, $feature_cvterm_id;
  }

  my $secondary_assigner_pmid = $self->secondary_assigner_pmid();
  my %secondary_annotations_to_delete = ();

  my $primary_sth = $dbh->prepare($query);

  $primary_sth->execute('' . $self->primary_assigner())
    or die ("Couldn't execute: " . $primary_sth->errstr);

  while (my ($feature_cvterm_id, $pmid, $gene_uniquename, $term_name, $residue, $evidence) = $primary_sth->fetchrow_array()) {
    $residue //= '';
    my $key = make_key($gene_uniquename, $term_name, $residue);

    my $secondary_annotations = $secondary_assigner_annotations{$key}->{$pmid};

    if (defined $secondary_annotations) {
      for my $secondary_annotation (@$secondary_annotations) {
        $secondary_annotations_to_delete{$secondary_annotation} =
          [$pmid, $gene_uniquename, $term_name, $residue];
      }
    }

    $secondary_annotations = $secondary_assigner_annotations{$key}->{$secondary_assigner_pmid};

    if (defined $secondary_annotations) {
      for my $secondary_annotation (@$secondary_annotations) {
        $secondary_annotations_to_delete{$secondary_annotation} =
          ['', $gene_uniquename, $term_name, $residue];
      }
    }
  }

  my $delete_count = scalar(keys %secondary_annotations_to_delete);
  warn "deleting $delete_count modifications\n";

  print "pmid\tgene\tterm_name\tresidue\n";

  my @feature_cvterm_ids_to_delete = ();

  for my $secondary_annotation_id (keys %secondary_annotations_to_delete) {
    my $row_to_delete = $secondary_annotations_to_delete{$secondary_annotation_id};

    push @feature_cvterm_ids_to_delete, $secondary_annotation_id;

    my $row_string = join "\t", @$row_to_delete;

    print $row_string, "\n";
  }
}

1;

