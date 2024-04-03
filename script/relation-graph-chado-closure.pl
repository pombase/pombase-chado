#!/usr/bin/env perl

use warnings;
use strict;

use File::Temp qw/ tempfile /;
use DBI;

use Cwd qw(cwd);
my $cwd = cwd;

if (@ARGV < 4) {
  die <<"EOF";
$0: ERROR: needs four or more arguments

This script is a wrapper for owltools with the --save-closure-for-chado
option.  The terms from the ontology files must be present in Chado
before running this script.

The OBO file arguments are passed to owltools and the output is stored in
the cvtermpath table via a temporary table.

Usage:
  $0 host database_name username password obo_file_name [obo_file_name ...]
EOF
}

my ($host, $database_name, $user, $pass, @filenames) = @ARGV;

my $dbh = DBI->connect("dbi:Pg:db=$database_name;host=$host", $user, $pass,
                       { AutoCommit => 0, PrintError => 1,
                         RaiseError => 1 })
  or die "Cannot connect to $database_name on $host: $DBI::errstr\n";

my $PURL_PREFIX = 'http://purl.obolibrary.org/obo';
my $line_re = qr|
  <\Q$PURL_PREFIX\E/([^/]+)>
  \s+
  <http://\S+[/#](.*)>
  \s+
  <\Q$PURL_PREFIX\E/([^/]+)>
|x;

my $temp_table_name = "owltools_closure_temp";

my @column_defs =
  ([qw|subj_db_id INTEGER REFERENCES db(db_id)|], [qw(subj_accession text)], [qw(rel_termid text)],
   [qw(pathdistance integer)],
   [qw|obj_db_id INTEGER REFERENCES db(db_id)|], [qw(obj_accession text)]);

my @column_names =
  map {
    $_->[0]
  } @column_defs;

my $column_defs_sql = join ", ",
   map {
     $_->[0] . ' ' . $_->[1] . ' NOT NULL';
   } @column_defs;

my %db_name_ids = ();

my $sth = $dbh->prepare("SELECT name, db_id FROM db");
$sth->execute();

while (my @data = $sth->fetchrow_array()) {
  $db_name_ids{$data[0]} = $data[1];
}

$dbh->do("TRUNCATE cvtermpath");

$dbh->do("CREATE TEMPORARY TABLE $temp_table_name ($column_defs_sql)");

$dbh->do("CREATE TEMPORARY TABLE ${temp_table_name}_termids AS (select t.name as term_name, db.name || ':' || x.accession as termid from cvterm t join dbxref x on t.dbxref_id = x.dbxref_id join db on x.db_id = db.db_id)");

sub _fix_term
{
  my $termid = shift;
  if ($termid =~ /^([A-Z]+)_(\d+)$/) {
    return "$1:$2";
  } else {
    return $termid
  }
}

for my $filename (@filenames) {
  my $column_name_sql = join ", ", @column_names;

  $dbh->do("COPY $temp_table_name($column_name_sql) FROM STDIN")
    or die "failed to COPY into $temp_table_name: ", $dbh->errstr, "\n";

  my ($temp_fh, $temp_filename) = tempfile();

  my $filename_full_path = $filename;

  if ($filename_full_path !~ m|^/|) {
    $filename_full_path = "$cwd/$filename_full_path";
  }

  warn "processing: $filename_full_path\n";

  system ("cd /var/pomcur/external/relation-graph-1.1; ./bin/relation-graph --ontology-file $filename_full_path --non-redundant-output-file /dev/null --redundant-output-file $temp_filename --mode rdf --output-subclasses true --reflexive-subclasses false --equivalence-as-subclass false") == 0
    or die "can't open pipe from owltools: $?";

  open my $owltools_out, '<', $temp_filename
    or die "can't open owltools output from $temp_filename: $!\n";

  while (defined (my $line = <$owltools_out>)) {
    chomp $line;

    if ($line =~ m|http://identifiers.org/hgnc|) {
      # skip HGNC objects
      next;
    }

    my ($subjectid, $rel_termid, $objectid) = $line =~ $line_re;
    my $pathdistance = 1;

    if (!$subjectid) {
      die "failed, can't parse: $line\n";
    }

    if ($rel_termid eq 'subClassOf') {
      $rel_termid = 'internal:is_a';
    } else {
      $rel_termid = _fix_term($rel_termid);
    }

    my ($subj_db_name, $subj_accession) = split /_/, $subjectid;

    next if $subj_db_name eq 'http' or $subj_db_name eq 'NCBITaxon';

    if (!defined $subj_accession) {
      die "$subjectid isn't in the form DB_NAME:ACCESSION\n";
    }

    my $subj_db_id = $db_name_ids{$subj_db_name};

    if (!defined $subj_db_id) {
      die "can't find a DB for: $subj_db_name\n";
    }

    my ($obj_db_name, $obj_accession) = split /_/, $objectid;

    next if $obj_db_name eq 'http' or $obj_db_name eq 'NCBITaxon';

    if (!defined $obj_accession) {
      die "$objectid isn't in the form DB_NAME:ACCESSION\n";
    }

    my $obj_db_id = $db_name_ids{$obj_db_name};

    if (!defined $obj_db_id) {
      die "can't find a DB for: $obj_db_name\n";
    }

    my $row =
      (join "\t",
       ($subj_db_id, $subj_accession, $rel_termid, $pathdistance,
        $obj_db_id, $obj_accession)) . "\n";

    if (!$dbh->pg_putcopydata($row)) {
      die $dbh->errstr();
    }
  }

  close $owltools_out or die "can't close pipe from owltools: $!";

  if (!$dbh->pg_putcopyend()) {
    die $dbh->errstr();
  }

  for my $minus ('', '-') {
    my $column_names;

    if ($minus eq '') {
      $column_names = "subject_id, type_id, object_id, cv_id, pathdistance";
    } else {
      $column_names = "object_id, type_id, subject_id, cv_id, pathdistance";
    }

    my $fill_path_sql = <<"SQL";
INSERT INTO cvtermpath ($column_names)
  (SELECT subject.cvterm_id, rel_type.cvterm_id, object.cvterm_id,
          subject.cv_id, ${minus}pathdistance
     FROM $temp_table_name closure
          JOIN dbxref subj_x ON closure.subj_db_id = subj_x.db_id
               AND closure.subj_accession = subj_x.accession
          JOIN cvterm subject ON subject.dbxref_id = subj_x.dbxref_id
          JOIN dbxref obj_x ON closure.obj_db_id = obj_x.db_id
               AND closure.obj_accession = obj_x.accession
          JOIN cvterm object ON object.dbxref_id = obj_x.dbxref_id
          JOIN ${temp_table_name}_termids ON closure.rel_termid = ${temp_table_name}_termids.termid
          JOIN cvterm rel_type ON ${temp_table_name}_termids.term_name = rel_type.name);
SQL

    $dbh->do($fill_path_sql);
  }

  $dbh->do("TRUNCATE $temp_table_name");
}

# add an entry with pathdistance = 0 for each term in each CV
my $null_path_sql = <<"EOF";
INSERT INTO cvtermpath (subject_id, object_id, cv_id, pathdistance, type_id)
 (WITH cvs AS
   (SELECT cv_id FROM cvterm WHERE cvterm_id IN (SELECT distinct(subject_id) AS cvterm_id FROM cvtermpath
     UNION SELECT distinct(object_id) AS cvterm_id FROM cvtermpath))
  SELECT cvterm_id, cvterm_id, 10, 0,
         (SELECT cvterm_id
            FROM cvterm t
            JOIN cv ON cv.cv_id = t.cv_id
           WHERE t.name = 'is_a' and cv.name = 'local')
         FROM cvterm WHERE cvterm.cv_id IN (SELECT cv_id FROM cvs));
EOF

$dbh->do($null_path_sql);

$dbh->commit();
