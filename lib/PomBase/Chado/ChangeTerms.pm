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
             "from_db_name TEXT, " .
             "from_accession TEXT, " .
             "to_db_name TEXT, " .
             "to_accession TEXT)");
#    $dbh->do("CREATE UNIQUE INDEX ${temp_table_name}_from_idx ON " .
#             "$temp_table_name(to_db_name)");

    my $sth = $dbh->prepare("INSERT INTO $temp_table_name(" .
                            "from_db_name, from_accession, to_db_name, to_accession) " .
                             "VALUES (?, ?, ?, ?)");

    for my $from_termid (keys %{$self->termid_map()}) {
      if (my ($from_db_name, $from_accession) = $from_termid =~ /(\w+):(\w+)/) {
        my $to_termid = $self->termid_map()->{$from_termid};

        if (my ($to_db_name, $to_accession) = $to_termid =~ /(\w+):(\w+)/) {
          $sth->execute($from_db_name, $from_accession, $to_db_name, $to_accession);
        } else {
          die "term id not in the form 'DB_NAME:ACCESSION': $to_termid\n";
        }
      } else {
        die "term id not in the form 'DB_NAME:ACCESSION': $from_termid\n";
      }
    }

    $dbh->do(<<"SQL"
CREATE TEMPORARY TABLE ${temp_table_name}_cv_db AS
   SELECT t.cvterm_id, db.name as db_name, x.accession
     FROM cvterm t JOIN dbxref x on t.dbxref_id = x.dbxref_id
                   JOIN db on x.db_id = db.db_id
SQL
);

    my $temp_cvterm_ids_table = "${temp_table_name}_cvterm_ids";

    $dbh->do(<<"SQL"
CREATE TEMPORARY TABLE $temp_cvterm_ids_table AS
  SELECT from_term_cv_db.cvterm_id AS from_cvterm_id,
         to_term_cv_db.cvterm_id AS to_cvterm_id
    FROM $temp_table_name tmp
         JOIN ${temp_table_name}_cv_db from_term_cv_db ON
              from_term_cv_db.db_name = tmp.from_db_name AND
              from_term_cv_db.accession = tmp.from_accession
         JOIN ${temp_table_name}_cv_db to_term_cv_db ON
              to_term_cv_db.db_name = tmp.to_db_name AND
              to_term_cv_db.accession = tmp.to_accession
SQL
);

    $sth = $dbh->prepare(<<"SQL"
SELECT pub.uniquename, f.uniquename, f.name,
       t_old.name, db_old.name || ':' || x_old.accession as old_termid,
       t_new.name, db_new.name || ':' || x_new.accession as new_termid
  FROM feature_cvterm fc1, feature_cvterm fc2,
       $temp_cvterm_ids_table ids
       JOIN feature f ON fc1.feature_id = f.feature_id
       JOIN pub ON pub.pub_id = fc1.pub_id
       JOIN cvterm t_old ON t_old.cvterm_id = ids.from_cvterm_id
       JOIN dbxref x_old ON x_old.dbxref_id = t_old.dbxref_id
       JOIN db db_old ON db_old.db_id = x_old.db_id
       JOIN cvterm t_new ON t_new.cvterm_id = ids.to_cvterm_id
       JOIN dbxref x_new ON x_new.dbxref_id = t_new.dbxref_id
       JOIN db db_new ON db_new.db_id = x_new.db_id
 WHERE fc2.cvterm_id = ids.from_cvterm_id
   AND fc1.feature_id = fc2.feature_id
   AND fc1.cvterm_id = ids.to_cvterm_id
   AND fc1.pub_id = fc2.pub_id
SQL
);
    $sth->execute();
    my $row_count = 0;
    while (my @data = $sth->fetchrow_array()) {
      if ($row_count == 0) {
        warn "These term changes aren't possible because resulting " .
          "feature_cvterm annotation would be duplicates:\n";
      }
      my ($pub_uniquename, $feature_uniquename, $feature_name,
          $old_term_name, $old_termid, $new_term_name, $new_termid) = @data;

      warn "  $pub_uniquename - $feature_uniquename" .
        (defined $feature_name ? "($feature_name)" : '') .
        "  $old_termid($old_term_name) -> $new_termid($new_term_name)";
      $row_count++;
    }


    $dbh->do(<<"SQL"
UPDATE feature_cvterm SET cvterm_id =
 (SELECT to_cvterm_id FROM $temp_cvterm_ids_table
   WHERE cvterm_id = from_cvterm_id)
 WHERE cvterm_id IN
   (SELECT from_cvterm_id FROM $temp_cvterm_ids_table)
SQL
);


# OR:
# update feature_cvterm set cvterm_id = to_cvterm_id from
# feature_cvterm fc inner join pombase_change_terms_temp on
# from_cvterm_id = fc.cvterm_id

  };

  $chado->txn_do($proc);
}

1;
