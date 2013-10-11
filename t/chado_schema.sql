-- This is a simplified Chado SQLite schema for testing.

PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE cv (
  cv_id INTEGER PRIMARY KEY NOT NULL,
  name varchar(255) NOT NULL,
  definition text
);
CREATE TABLE cvprop (
  cvprop_id INTEGER PRIMARY KEY NOT NULL,
  cv_id integer NOT NULL,
  type_id integer NOT NULL,
  value text,
  rank integer NOT NULL DEFAULT 0
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
CREATE TABLE dbxrefprop (
  dbxrefprop_id INTEGER PRIMARY KEY NOT NULL,
  dbxref_id integer NOT NULL,
  type_id integer NOT NULL,
  value text NOT NULL DEFAULT '',
  rank integer NOT NULL DEFAULT 0
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
CREATE TABLE featureloc_pub (
  featureloc_pub_id INTEGER PRIMARY KEY NOT NULL,
  featureloc_id integer NOT NULL,
  pub_id integer NOT NULL
);
CREATE TABLE featureprop_pub (
  featureprop_pub_id INTEGER PRIMARY KEY NOT NULL,
  featureprop_id integer NOT NULL,
  pub_id integer NOT NULL
);
CREATE TABLE organism (
  organism_id INTEGER PRIMARY KEY NOT NULL,
  abbreviation varchar(255),
  genus varchar(255) NOT NULL,
  species varchar(255) NOT NULL,
  common_name varchar(255),
  comment text
);
CREATE TABLE organism_dbxref (
  organism_dbxref_id INTEGER PRIMARY KEY NOT NULL,
  organism_id integer NOT NULL,
  dbxref_id integer NOT NULL
);
CREATE TABLE organismprop (
  organismprop_id INTEGER PRIMARY KEY NOT NULL,
  organism_id integer NOT NULL,
  type_id integer NOT NULL,
  value text,
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE phylonode (
  phylonode_id INTEGER PRIMARY KEY NOT NULL,
  phylotree_id integer NOT NULL,
  parent_phylonode_id integer,
  left_idx integer NOT NULL,
  right_idx integer NOT NULL,
  type_id integer,
  feature_id integer,
  label varchar(255),
  distance double precision
);
CREATE TABLE phylonode_dbxref (
  phylonode_dbxref_id INTEGER PRIMARY KEY NOT NULL,
  phylonode_id integer NOT NULL,
  dbxref_id integer NOT NULL
);
CREATE TABLE phylonode_organism (
  phylonode_organism_id INTEGER PRIMARY KEY NOT NULL,
  phylonode_id integer NOT NULL,
  organism_id integer NOT NULL
);
CREATE TABLE phylonode_pub (
  phylonode_pub_id INTEGER PRIMARY KEY NOT NULL,
  phylonode_id integer NOT NULL,
  pub_id integer NOT NULL
);
CREATE TABLE phylonode_relationship (
  phylonode_relationship_id INTEGER PRIMARY KEY NOT NULL,
  subject_id integer NOT NULL,
  object_id integer NOT NULL,
  type_id integer NOT NULL,
  rank integer,
  phylotree_id integer NOT NULL
);
CREATE TABLE phylonodeprop (
  phylonodeprop_id INTEGER PRIMARY KEY NOT NULL,
  phylonode_id integer NOT NULL,
  type_id integer NOT NULL,
  value text NOT NULL DEFAULT '',
  rank integer NOT NULL DEFAULT 0
);
CREATE TABLE phylotree (
  phylotree_id INTEGER PRIMARY KEY NOT NULL,
  dbxref_id integer NOT NULL,
  name varchar(255),
  type_id integer,
  analysis_id integer,
  comment text
);
CREATE TABLE phylotree_pub (
  phylotree_pub_id INTEGER PRIMARY KEY NOT NULL,
  phylotree_id integer NOT NULL,
  pub_id integer NOT NULL
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
CREATE TABLE pub_relationship (
  pub_relationship_id INTEGER PRIMARY KEY NOT NULL,
  subject_id integer NOT NULL,
  object_id integer NOT NULL,
  type_id integer NOT NULL
);
CREATE TABLE pubauthor (
  pubauthor_id INTEGER PRIMARY KEY NOT NULL,
  pub_id integer NOT NULL,
  rank integer NOT NULL,
  editor boolean DEFAULT false,
  surname varchar(100) NOT NULL,
  givennames varchar(100),
  suffix varchar(100)
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
CREATE INDEX cvprop_idx_cv_id ON cvprop (cv_id);
CREATE INDEX cvprop_idx_type_id ON cvprop (type_id);
CREATE UNIQUE INDEX cvprop_c1 ON cvprop (cv_id, type_id, rank);
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
CREATE INDEX dbxrefprop_idx_dbxref_id ON dbxrefprop (dbxref_id);
CREATE INDEX dbxrefprop_idx_type_id ON dbxrefprop (type_id);
CREATE UNIQUE INDEX dbxrefprop_c1 ON dbxrefprop (dbxref_id, type_id, rank);
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
CREATE INDEX featureloc_pub_idx_featureloc_id ON featureloc_pub (featureloc_id);
CREATE INDEX featureloc_pub_idx_pub_id ON featureloc_pub (pub_id);
CREATE UNIQUE INDEX featureloc_pub_c1 ON featureloc_pub (featureloc_id, pub_id);
CREATE INDEX featureprop_pub_idx_featureprop_id ON featureprop_pub (featureprop_id);
CREATE INDEX featureprop_pub_idx_pub_id ON featureprop_pub (pub_id);
CREATE UNIQUE INDEX featureprop_pub_c1 ON featureprop_pub (featureprop_id, pub_id);
CREATE UNIQUE INDEX organism_c1 ON organism (genus, species);
CREATE INDEX organism_dbxref_idx_dbxref_id ON organism_dbxref (dbxref_id);
CREATE INDEX organism_dbxref_idx_organism_id ON organism_dbxref (organism_id);
CREATE UNIQUE INDEX organism_dbxref_c1 ON organism_dbxref (organism_id, dbxref_id);
CREATE INDEX organismprop_idx_organism_id ON organismprop (organism_id);
CREATE INDEX organismprop_idx_type_id ON organismprop (type_id);
CREATE UNIQUE INDEX organismprop_c1 ON organismprop (organism_id, type_id, rank);
CREATE INDEX phylonode_idx_feature_id ON phylonode (feature_id);
CREATE INDEX phylonode_idx_phylotree_id ON phylonode (phylotree_id);
CREATE INDEX phylonode_idx_parent_phylonode_id ON phylonode (parent_phylonode_id);
CREATE INDEX phylonode_idx_type_id ON phylonode (type_id);
CREATE UNIQUE INDEX phylonode_phylotree_id_key ON phylonode (phylotree_id, left_idx);
CREATE UNIQUE INDEX phylonode_phylotree_id_key1 ON phylonode (phylotree_id, right_idx);
CREATE INDEX phylonode_dbxref_idx_dbxref_id ON phylonode_dbxref (dbxref_id);
CREATE INDEX phylonode_dbxref_idx_phylonode_id ON phylonode_dbxref (phylonode_id);
CREATE UNIQUE INDEX phylonode_dbxref_phylonode_id_key ON phylonode_dbxref (phylonode_id, dbxref_id);
CREATE INDEX phylonode_organism_idx_organism_id ON phylonode_organism (organism_id);
CREATE UNIQUE INDEX phylonode_organism_phylonode_id_key ON phylonode_organism (phylonode_id);
CREATE INDEX phylonode_pub_idx_phylonode_id ON phylonode_pub (phylonode_id);
CREATE INDEX phylonode_pub_idx_pub_id ON phylonode_pub (pub_id);
CREATE UNIQUE INDEX phylonode_pub_phylonode_id_key ON phylonode_pub (phylonode_id, pub_id);
CREATE INDEX phylonode_relationship_idx_object_id ON phylonode_relationship (object_id);
CREATE INDEX phylonode_relationship_idx_phylotree_id ON phylonode_relationship (phylotree_id);
CREATE INDEX phylonode_relationship_idx_subject_id ON phylonode_relationship (subject_id);
CREATE INDEX phylonode_relationship_idx_type_id ON phylonode_relationship (type_id);
CREATE UNIQUE INDEX phylonode_relationship_subject_id_key ON phylonode_relationship (subject_id, object_id, type_id);
CREATE INDEX phylonodeprop_idx_phylonode_id ON phylonodeprop (phylonode_id);
CREATE INDEX phylonodeprop_idx_type_id ON phylonodeprop (type_id);
CREATE UNIQUE INDEX phylonodeprop_phylonode_id_key ON phylonodeprop (phylonode_id, type_id, value, rank);
CREATE INDEX phylotree_idx_analysis_id ON phylotree (analysis_id);
CREATE INDEX phylotree_idx_dbxref_id ON phylotree (dbxref_id);
CREATE INDEX phylotree_idx_type_id ON phylotree (type_id);
CREATE INDEX phylotree_pub_idx_phylotree_id ON phylotree_pub (phylotree_id);
CREATE INDEX phylotree_pub_idx_pub_id ON phylotree_pub (pub_id);
CREATE UNIQUE INDEX phylotree_pub_phylotree_id_key ON phylotree_pub (phylotree_id, pub_id);
CREATE INDEX pub_idx_type_id ON pub (type_id);
CREATE UNIQUE INDEX pub_c1 ON pub (uniquename);
CREATE INDEX pub_dbxref_idx_dbxref_id ON pub_dbxref (dbxref_id);
CREATE INDEX pub_dbxref_idx_pub_id ON pub_dbxref (pub_id);
CREATE UNIQUE INDEX pub_dbxref_c1 ON pub_dbxref (pub_id, dbxref_id);
CREATE INDEX pub_relationship_idx_object_id ON pub_relationship (object_id);
CREATE INDEX pub_relationship_idx_subject_id ON pub_relationship (subject_id);
CREATE INDEX pub_relationship_idx_type_id ON pub_relationship (type_id);
CREATE UNIQUE INDEX pub_relationship_c1 ON pub_relationship (subject_id, object_id, type_id);
CREATE INDEX pubauthor_idx_pub_id ON pubauthor (pub_id);
CREATE UNIQUE INDEX pubauthor_c1 ON pubauthor (pub_id, rank);
CREATE INDEX pubprop_idx_pub_id ON pubprop (pub_id);
CREATE INDEX pubprop_idx_type_id ON pubprop (type_id);
CREATE UNIQUE INDEX pubprop_c1 ON pubprop (pub_id, type_id, rank);
CREATE INDEX synonym_idx_type_id ON synonym (type_id);
CREATE UNIQUE INDEX synonym_c1 ON synonym (name, type_id);
CREATE INDEX featureprop_idx_type_id ON featureprop (type_id);
CREATE INDEX featureprop_idx_feature_id ON featureprop (feature_id);
CREATE UNIQUE INDEX featureprop_c1 ON featureprop (feature_id, type_id, rank);
COMMIT;
