package PomBase::Chado::GoFilterDuplicateAssigner;

=head1 NAME

PomBase::Chado::GoFilterDuplicateAssigner - Remove duplicates caused by annotation
     from multiple sources and log those annotations that are removed

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::GoFilterDuplicateAssigner

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

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has primary_assigner => (is => 'rw', init_arg => undef);
has secondary_assigner => (is => 'rw', init_arg => undef);

=head2 process

 Usage : my $filter = PomBase::Chado::GoFilterDuplicateAssigner->new(config => $config,
                                                                  chado => $chado);
         $filter->process();
 Func  : If an annotation comes from multiple sources, keep just one and write
         a log of those that are removed
 Args  : $config - a Config object
         $chado - a schema object of the Chado database
 Return: nothing, dies on error

=cut


sub BUILD
{
  my $self = shift;

  my $primary_assigner = undef;
  my $secondary_assigner = undef;

  my @opt_config = ('primary-assigner=s' => \$primary_assigner,
                    'secondary-assigner=s' => \$secondary_assigner);

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

  $self->primary_assigner($primary_assigner);
  $self->secondary_assigner($secondary_assigner);
}

sub _key_from_row
{
  my @row = @_;

  shift @row;

  return join '-=:=-', @row;
}

sub process
{

  my $self = shift;

  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $query = <<'EOQ';
SELECT fc.feature_cvterm_id,
       t.name AS term_name,
       db.name || ':' || dbxref.accession as term_id,
       base_cv_name,
       f.uniquename AS feature_uniquename,
       array_to_string(array
                         (SELECT value
                          FROM feature_cvtermprop p
                          JOIN cvterm t ON t.cvterm_id = p.type_id
                          WHERE p.feature_cvterm_id = fc.feature_cvterm_id
                            AND t.name = 'evidence'), ',') AS evidence,
       array_to_string(array
                         (SELECT value
                          FROM feature_cvtermprop p
                          JOIN cvterm t ON t.cvterm_id = p.type_id
                          WHERE p.feature_cvterm_id = fc.feature_cvterm_id
                            AND t.name = 'with'
                          ORDER BY value), ',') AS with_value,
       array_to_string(array
                         (SELECT value
                          FROM feature_cvtermprop p
                          JOIN cvterm t ON t.cvterm_id = p.type_id
                          WHERE p.feature_cvterm_id = fc.feature_cvterm_id
                            AND t.name = 'from'
                          ORDER BY value), ',') AS
FROM,
       array_to_string(array
                         (SELECT value
                          FROM feature_cvtermprop p
                          JOIN cvterm t ON t.cvterm_id = p.type_id
                          WHERE p.feature_cvterm_id = fc.feature_cvterm_id
                            AND t.name = 'gene_product_form_id'
                          ORDER BY value), ',') AS gene_product_form_id,
       array_to_string(array
                         (SELECT value
                          FROM feature_cvtermprop p
                          JOIN cvterm t ON t.cvterm_id = p.type_id
                          WHERE p.feature_cvterm_id = fc.feature_cvterm_id
                            AND t.name = 'qualifier'
                          ORDER BY value), ',') AS qualifier,
       pub.uniquename AS pmid
FROM feature f
JOIN pombase_feature_cvterm_ext_resolved_terms fc ON fc.feature_id = f.feature_id
JOIN cvterm t ON fc.cvterm_id = t.cvterm_id
JOIN dbxref ON t.dbxref_id = dbxref.dbxref_id
JOIN db on dbxref.db_id = db.db_id
JOIN cv ON t.cv_id = cv.cv_id
JOIN cvterm ft ON f.type_id = ft.cvterm_id
JOIN feature_cvtermprop fcp ON fcp.feature_cvterm_id = fc.feature_cvterm_id
JOIN cvterm fcpt ON fcpt.cvterm_id = fcp.type_id
JOIN pub ON fc.pub_id = pub.pub_id
WHERE fcpt.name = 'assigned_by'
  AND base_cv_name in ('molecular_function',
                       'biological_process',
                       'cellular_component')
  AND fcp.value = ?;
EOQ

  my $sth = $dbh->prepare($query);
  $sth->execute('' . $self->secondary_assigner()) or die ("Couldn't execute: " . $sth->errstr);

  my %secondary_assigner_annotations = ();

  while (my @row = $sth->fetchrow_array()) {
    my $key = _key_from_row(@row);

    $secondary_assigner_annotations{$key} = \@row;
  }

  $sth = $dbh->prepare($query);
  $sth->execute('' . $self->primary_assigner()) or die ("Couldn't execute: " . $sth->errstr);

  my @secondary_annotations_to_delete = ();

  while (my @row = $sth->fetchrow_array()) {
    my $key = _key_from_row(@row);

    my $secondary_row = $secondary_assigner_annotations{$key};

    if (defined $secondary_row) {
      push @secondary_annotations_to_delete, $secondary_row;
    }
  }

  print "term_name\tterm_id\tcv_name\tfeature\tevidence\twith\tfrom\tgene_product_form_id\tqualifier\tpmid\n";

  my @feature_cvterm_ids_to_delete = ();

  for my $row_to_delete (@secondary_annotations_to_delete) {
    my $feature_cvterm_id = shift @$row_to_delete;

    push @feature_cvterm_ids_to_delete, $feature_cvterm_id;

    my $row_string = join "\t", @$row_to_delete;

    print $row_string, "\n";
  }

  my $delete_count = scalar(@feature_cvterm_ids_to_delete);

  warn "deleting $delete_count annotations\n";

  my $bind_bit = join ",", (('?') x scalar(@feature_cvterm_ids_to_delete));

  $sth = $dbh->prepare("delete from feature_cvterm where feature_cvterm_id in ($bind_bit)");
  $sth->execute(@feature_cvterm_ids_to_delete);
}

1;
