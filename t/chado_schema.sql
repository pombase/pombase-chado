-- This is a simplified Chado SQLite schema for testing.

PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE cv (
  cv_id INTEGER PRIMARY KEY NOT NULL,
  name varchar(255) NOT NULL,
  definition text
);
CREATE TABLE cvterm (
  cvterm_id INTEGER PRIMARY KEY NOT NULL,
  cv_id integer NOT NULL,
  name varchar(1024) NOT NULL,
  definition text,
  dbxref_id integer NOT NULL,
  is_obsolete integer NOT NULL DEFAULT 0,
  is_relationshiptype integer NOT NULL DEFAULT 0
);
CREATE TABLE cvterm_dbxref (
  cvterm_dbxref_id INTEGER PRIMARY KEY NOT NULL,
  cvterm_id integer NOT NULL,
  dbxref_id integer NOT NULL,
  is_for_definition integer NOT NULL DEFAULT 0
);
CREATE TABLE cvterm_relationship (
  cvterm_relationship_id INTEGER PRIMARY KEY NOT NULL,
  type_id integer NOT NULL,
  subject_id integer NOT NULL,
  object_id integer NOT NULL
);
CREATE TABLE cvtermpath (
  cvtermpath_id INTEGER PRIMARY KEY NOT NULL,
  type_id integer,
  subject_id integer NOT NULL,
  object_id integer NOT NULL,
  cv_id integer NOT NULL,
  pathdistance integer
);
CREATE TABLE cvtermprop (
  cvtermprop_id INTEGER PRIMARY KEY NOT NULL,
  cvterm_id integer NOT NULL,
  type_id integer NOT NULL,
  value text NOT NULL DEFAULT '',
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE cvtermsynonym (
  cvtermsynonym_id INTEGER PRIMARY KEY NOT NULL,
  cvterm_id integer NOT NULL,
  synonym varchar(1024) NOT NULL,
  type_id integer
);
CREATE TABLE db (
  db_id INTEGER PRIMARY KEY NOT NULL,
  name varchar(255) NOT NULL,
  description varchar(255),
  urlprefix varchar(255),
  url varchar(255)
);
CREATE TABLE dbxref (
  dbxref_id INTEGER PRIMARY KEY NOT NULL,
  db_id integer NOT NULL,
  accession varchar(255) NOT NULL,
  version varchar(255) NOT NULL DEFAULT '',
  description text
);
CREATE TABLE feature (
  feature_id INTEGER PRIMARY KEY NOT NULL,
  dbxref_id integer,
  organism_id integer NOT NULL,
  name varchar(255),
  uniquename text NOT NULL,
  residues text,
  seqlen integer,
  md5checksum char(32),
  type_id integer NOT NULL,
  is_analysis boolean NOT NULL DEFAULT false,
  is_obsolete boolean NOT NULL DEFAULT false,
  timeaccessioned timestamp NOT NULL DEFAULT current_timestamp,
  timelastmodified timestamp NOT NULL DEFAULT current_timestamp
);
CREATE TABLE feature_cvterm (
  feature_cvterm_id INTEGER PRIMARY KEY NOT NULL,
  feature_id integer NOT NULL,
  cvterm_id integer NOT NULL,
  pub_id integer NOT NULL,
  is_not boolean NOT NULL DEFAULT false,
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE feature_cvterm_dbxref (
  feature_cvterm_dbxref_id INTEGER PRIMARY KEY NOT NULL,
  feature_cvterm_id integer NOT NULL,
  dbxref_id integer NOT NULL
);
CREATE TABLE feature_cvterm_pub (
  feature_cvterm_pub_id INTEGER PRIMARY KEY NOT NULL,
  feature_cvterm_id integer NOT NULL,
  pub_id integer NOT NULL
);
CREATE TABLE feature_cvtermprop (
  feature_cvtermprop_id INTEGER PRIMARY KEY NOT NULL,
  feature_cvterm_id integer NOT NULL,
  type_id integer NOT NULL,
  value text,
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE feature_dbxref (
  feature_dbxref_id INTEGER PRIMARY KEY NOT NULL,
  feature_id integer NOT NULL,
  dbxref_id integer NOT NULL,
  is_current boolean NOT NULL DEFAULT true
);
CREATE TABLE feature_pub (
  feature_pub_id INTEGER PRIMARY KEY NOT NULL,
  feature_id integer NOT NULL,
  pub_id integer NOT NULL
);
CREATE TABLE feature_pubprop (
  feature_pubprop_id INTEGER PRIMARY KEY NOT NULL,
  feature_pub_id integer NOT NULL,
  type_id integer NOT NULL,
  value text,
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE feature_relationship (
  feature_relationship_id INTEGER PRIMARY KEY NOT NULL,
  subject_id integer NOT NULL,
  object_id integer NOT NULL,
  type_id integer NOT NULL,
  value text,
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE feature_relationship_pub (
  feature_relationship_pub_id INTEGER PRIMARY KEY NOT NULL,
  feature_relationship_id integer NOT NULL,
  pub_id integer NOT NULL
);
CREATE TABLE feature_relationshipprop (
  feature_relationshipprop_id INTEGER PRIMARY KEY NOT NULL,
  feature_relationship_id integer NOT NULL,
  type_id integer NOT NULL,
  value text,
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE feature_relationshipprop_pub (
  feature_relationshipprop_pub_id INTEGER PRIMARY KEY NOT NULL,
  feature_relationshipprop_id integer NOT NULL,
  pub_id integer NOT NULL
);
CREATE TABLE feature_synonym (
  feature_synonym_id INTEGER PRIMARY KEY NOT NULL,
  synonym_id integer NOT NULL,
  feature_id integer NOT NULL,
  pub_id integer NOT NULL,
  is_current boolean NOT NULL DEFAULT false,
  is_internal boolean NOT NULL DEFAULT false
);
CREATE TABLE featureloc (
  featureloc_id INTEGER PRIMARY KEY NOT NULL,
  feature_id integer NOT NULL,
  srcfeature_id integer,
  fmin integer,
  is_fmin_partial boolean NOT NULL DEFAULT false,
  fmax integer,
  is_fmax_partial boolean NOT NULL DEFAULT false,
  strand smallint,
  phase integer,
  residue_info text,
  locgroup integer NOT NULL DEFAULT 0,
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE organism (
  organism_id INTEGER PRIMARY KEY NOT NULL,
  abbreviation varchar(255),
  genus varchar(255) NOT NULL,
  species varchar(255) NOT NULL,
  common_name varchar(255),
  comment text
);
CREATE TABLE organismprop (
  organismprop_id INTEGER PRIMARY KEY NOT NULL,
  organism_id integer NOT NULL,
  type_id integer NOT NULL,
  value text,
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE pub (
  pub_id INTEGER PRIMARY KEY NOT NULL,
  title text,
  volumetitle text,
  volume varchar(255),
  series_name varchar(255),
  issue varchar(255),
  pyear varchar(255),
  pages varchar(255),
  miniref varchar(255),
  uniquename text NOT NULL,
  type_id integer NOT NULL,
  is_obsolete boolean DEFAULT false,
  publisher varchar(255),
  pubplace varchar(255)
);
CREATE TABLE pub_dbxref (
  pub_dbxref_id INTEGER PRIMARY KEY NOT NULL,
  pub_id integer NOT NULL,
  dbxref_id integer NOT NULL,
  is_current boolean NOT NULL DEFAULT true
);
CREATE TABLE pubprop (
  pubprop_id INTEGER PRIMARY KEY NOT NULL,
  pub_id integer NOT NULL,
  type_id integer NOT NULL,
  value text NOT NULL,
  rank integer
);
CREATE TABLE synonym (
  synonym_id INTEGER PRIMARY KEY NOT NULL,
  name varchar(255) NOT NULL,
  type_id integer NOT NULL,
  synonym_sgml varchar(255) NOT NULL
);
CREATE TABLE featureprop (
  featureprop_id INTEGER PRIMARY KEY NOT NULL,
  feature_id integer NOT NULL,
  type_id integer NOT NULL,
  value text,
  rank integer NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX cv_c1 ON cv (name);
CREATE INDEX cvterm_idx_cv_id ON cvterm (cv_id);
CREATE INDEX cvterm_idx_dbxref_id ON cvterm (dbxref_id);
CREATE UNIQUE INDEX cvterm_c1 ON cvterm (name, cv_id, is_obsolete);
CREATE UNIQUE INDEX cvterm_c2 ON cvterm (dbxref_id);
CREATE INDEX cvterm_dbxref_idx_cvterm_id ON cvterm_dbxref (cvterm_id);
CREATE INDEX cvterm_dbxref_idx_dbxref_id ON cvterm_dbxref (dbxref_id);
CREATE UNIQUE INDEX cvterm_dbxref_c1 ON cvterm_dbxref (cvterm_id, dbxref_id);
CREATE INDEX cvterm_relationship_idx_object_id ON cvterm_relationship (object_id);
CREATE INDEX cvterm_relationship_idx_subject_id ON cvterm_relationship (subject_id);
CREATE INDEX cvterm_relationship_idx_type_id ON cvterm_relationship (type_id);
CREATE UNIQUE INDEX cvterm_relationship_c1 ON cvterm_relationship (subject_id, object_id, type_id);
CREATE INDEX cvtermpath_idx_cv_id ON cvtermpath (cv_id);
CREATE INDEX cvtermpath_idx_object_id ON cvtermpath (object_id);
CREATE INDEX cvtermpath_idx_subject_id ON cvtermpath (subject_id);
CREATE INDEX cvtermpath_idx_type_id ON cvtermpath (type_id);
CREATE UNIQUE INDEX cvtermpath_c1 ON cvtermpath (subject_id, object_id, type_id, pathdistance);
CREATE INDEX cvtermprop_idx_cvterm_id ON cvtermprop (cvterm_id);
CREATE INDEX cvtermprop_idx_type_id ON cvtermprop (type_id);
CREATE UNIQUE INDEX cvtermprop_cvterm_id_key ON cvtermprop (cvterm_id, type_id, value, rank);
CREATE INDEX cvtermsynonym_idx_cvterm_id ON cvtermsynonym (cvterm_id);
CREATE INDEX cvtermsynonym_idx_type_id ON cvtermsynonym (type_id);
CREATE UNIQUE INDEX cvtermsynonym_c1 ON cvtermsynonym (cvterm_id, synonym);
CREATE UNIQUE INDEX db_c1 ON db (name);
CREATE INDEX dbxref_idx_db_id ON dbxref (db_id);
CREATE UNIQUE INDEX dbxref_c1 ON dbxref (db_id, accession, version);
CREATE INDEX feature_idx_dbxref_id ON feature (dbxref_id);
CREATE INDEX feature_idx_organism_id ON feature (organism_id);
CREATE INDEX feature_idx_type_id ON feature (type_id);
CREATE UNIQUE INDEX feature_c1 ON feature (organism_id, uniquename, type_id);
CREATE INDEX feature_cvterm_idx_cvterm_id ON feature_cvterm (cvterm_id);
CREATE INDEX feature_cvterm_idx_feature_id ON feature_cvterm (feature_id);
CREATE INDEX feature_cvterm_idx_pub_id ON feature_cvterm (pub_id);
CREATE UNIQUE INDEX feature_cvterm_c1 ON feature_cvterm (feature_id, cvterm_id, pub_id, rank);
CREATE INDEX feature_cvterm_dbxref_idx_dbxref_id ON feature_cvterm_dbxref (dbxref_id);
CREATE INDEX feature_cvterm_dbxref_idx_feature_cvterm_id ON feature_cvterm_dbxref (feature_cvterm_id);
CREATE UNIQUE INDEX feature_cvterm_dbxref_c1 ON feature_cvterm_dbxref (feature_cvterm_id, dbxref_id);
CREATE INDEX feature_cvterm_pub_idx_feature_cvterm_id ON feature_cvterm_pub (feature_cvterm_id);
CREATE INDEX feature_cvterm_pub_idx_pub_id ON feature_cvterm_pub (pub_id);
CREATE UNIQUE INDEX feature_cvterm_pub_c1 ON feature_cvterm_pub (feature_cvterm_id, pub_id);
CREATE INDEX feature_cvtermprop_idx_feature_cvterm_id ON feature_cvtermprop (feature_cvterm_id);
CREATE INDEX feature_cvtermprop_idx_type_id ON feature_cvtermprop (type_id);
CREATE UNIQUE INDEX feature_cvtermprop_c1 ON feature_cvtermprop (feature_cvterm_id, type_id, rank);
CREATE INDEX feature_dbxref_idx_dbxref_id ON feature_dbxref (dbxref_id);
CREATE INDEX feature_dbxref_idx_feature_id ON feature_dbxref (feature_id);
CREATE UNIQUE INDEX feature_dbxref_c1 ON feature_dbxref (feature_id, dbxref_id);
CREATE UNIQUE INDEX feature_pub_c1 ON feature_pub (feature_id, pub_id);
CREATE INDEX feature_pubprop_idx_feature_pub_id ON feature_pubprop (feature_pub_id);
CREATE INDEX feature_pubprop_idx_type_id ON feature_pubprop (type_id);
CREATE UNIQUE INDEX feature_pubprop_c1 ON feature_pubprop (feature_pub_id, type_id, rank);
CREATE INDEX feature_relationship_idx_object_id ON feature_relationship (object_id);
CREATE INDEX feature_relationship_idx_subject_id ON feature_relationship (subject_id);
CREATE INDEX feature_relationship_idx_type_id ON feature_relationship (type_id);
CREATE UNIQUE INDEX feature_relationship_c1 ON feature_relationship (subject_id, object_id, type_id, rank);
CREATE INDEX feature_relationship_pub_idx_feature_relationship_id ON feature_relationship_pub (feature_relationship_id);
CREATE INDEX feature_relationship_pub_idx_pub_id ON feature_relationship_pub (pub_id);
CREATE UNIQUE INDEX feature_relationship_pub_c1 ON feature_relationship_pub (feature_relationship_id, pub_id);
CREATE INDEX feature_relationshipprop_idx_feature_relationship_id ON feature_relationshipprop (feature_relationship_id);
CREATE INDEX feature_relationshipprop_idx_type_id ON feature_relationshipprop (type_id);
CREATE UNIQUE INDEX feature_relationshipprop_c1 ON feature_relationshipprop (feature_relationship_id, type_id, rank);
CREATE INDEX feature_relationshipprop_pub_idx_feature_relationshipprop_id ON feature_relationshipprop_pub (feature_relationshipprop_id);
CREATE INDEX feature_relationshipprop_pub_idx_pub_id ON feature_relationshipprop_pub (pub_id);
CREATE UNIQUE INDEX feature_relationshipprop_pub_c1 ON feature_relationshipprop_pub (feature_relationshipprop_id, pub_id);
CREATE INDEX feature_synonym_idx_feature_id ON feature_synonym (feature_id);
CREATE INDEX feature_synonym_idx_pub_id ON feature_synonym (pub_id);
CREATE INDEX feature_synonym_idx_synonym_id ON feature_synonym (synonym_id);
CREATE UNIQUE INDEX feature_synonym_c1 ON feature_synonym (synonym_id, feature_id, pub_id);
CREATE INDEX featureloc_idx_feature_id ON featureloc (feature_id);
CREATE INDEX featureloc_idx_srcfeature_id ON featureloc (srcfeature_id);
CREATE UNIQUE INDEX featureloc_c1 ON featureloc (feature_id, locgroup, rank);
CREATE UNIQUE INDEX organism_c1 ON organism (genus, species);
CREATE INDEX organismprop_idx_organism_id ON organismprop (organism_id);
CREATE INDEX organismprop_idx_type_id ON organismprop (type_id);
CREATE UNIQUE INDEX organismprop_c1 ON organismprop (organism_id, type_id, rank);
CREATE INDEX pub_idx_type_id ON pub (type_id);
CREATE UNIQUE INDEX pub_c1 ON pub (uniquename);
CREATE INDEX pub_dbxref_idx_dbxref_id ON pub_dbxref (dbxref_id);
CREATE INDEX pub_dbxref_idx_pub_id ON pub_dbxref (pub_id);
CREATE UNIQUE INDEX pub_dbxref_c1 ON pub_dbxref (pub_id, dbxref_id);
CREATE INDEX pubprop_idx_pub_id ON pubprop (pub_id);
CREATE INDEX pubprop_idx_type_id ON pubprop (type_id);
CREATE UNIQUE INDEX pubprop_c1 ON pubprop (pub_id, type_id, rank);
CREATE INDEX synonym_idx_type_id ON synonym (type_id);
CREATE UNIQUE INDEX synonym_c1 ON synonym (name, type_id);
CREATE INDEX featureprop_idx_type_id ON featureprop (type_id);
CREATE INDEX featureprop_idx_feature_id ON featureprop (feature_id);
CREATE UNIQUE INDEX featureprop_c1 ON featureprop (feature_id, type_id, rank);

CREATE VIEW pombase_feature_cvterm_with_ext_parents AS SELECT fc.feature_cvterm_id, fc.feature_id, pub_id, parent_t.name AS base_cvterm_name, parent_t.cvterm_id AS base_cvterm_id, parent_cv.name AS base_cv_name, child_t.name as cvterm_name, child_t.cvterm_id as cvterm_id FROM feature_cvterm fc JOIN cvterm child_t ON child_t.cvterm_id = fc.cvterm_id JOIN cvterm_relationship r ON child_t.cvterm_id = r.subject_id JOIN cvterm parent_t ON r.object_id = parent_t.cvterm_id JOIN cv parent_cv ON parent_cv.cv_id = parent_t.cv_id JOIN cv child_cv ON child_cv.cv_id = child_t.cv_id JOIN cvterm r_type ON r.type_id = r_type.cvterm_id WHERE r_type.name = 'is_a' AND child_cv.name = 'PomBase annotation extension terms';
CREATE VIEW pombase_feature_cvterm_no_ext_terms AS SELECT fc.feature_cvterm_id, fc.feature_id, pub_id, t.name AS base_cvterm_name, t.cvterm_id AS base_cvterm_id, cv.name AS base_cv_name, t.name as cvterm_name, t.cvterm_id FROM feature_cvterm fc JOIN cvterm t ON t.cvterm_id = fc.cvterm_id JOIN cv ON cv.cv_id = t.cv_id WHERE cv.name <> 'PomBase annotation extension terms';
CREATE VIEW pombase_feature_cvterm_ext_resolved_terms AS SELECT * from pombase_feature_cvterm_no_ext_terms UNION SELECT * from pombase_feature_cvterm_with_ext_parents;

COMMIT;
