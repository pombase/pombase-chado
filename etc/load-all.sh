#!/bin/bash -

# run script/make-db first

date

set -o pipefail

HOST=$1
DB=$2
USER=$3
PASSWORD=$4

LOG_DIR=`pwd`

SOURCES=/var/pomcur/sources

GOA_GAF_URL=ftp://ftp.ebi.ac.uk/pub/databases/GO/goa/UNIPROT/gene_association.goa_uniprot.gz

cd $SOURCES/pombe-embl/
svn update || exit 1

cd $HOME/git/pombase-run
git pull || exit 1

export PERL5LIB=$HOME/git/pombase-run/lib

cd $LOG_DIR
log_file=log.`date_string`
$HOME/git/pombase-run/script/load-chado.pl \
  --mapping "sequence_feature:sequence:$SOURCES/pombe-embl/chado_load_mappings/features-to-so_mapping_only.txt" \
  --mapping "pt_mod:PSI-MOD:$SOURCES/pombe-embl/chado_load_mappings/modification_map.txt" \
  --mapping "phenotype:fission_yeast_phenotype:$SOURCES/pombe-embl/chado_load_mappings/phenotype-map.txt" \
  --gene-ex-qualifiers $SOURCES/pombe-embl/supporting_files/gene_ex_qualifiers \
  --obsolete-term-map $HOME/pombe/go-doc/obsoletes-exact $HOME/git/pombase-run/load-chado.yaml \
  $HOST $DB $USER $PASSWORD $SOURCES/pombe-embl/*.contig 2>&1 | tee $log_file || exit 1

$HOME/git/pombase-run/etc/process-log.pl $log_file

echo starting import of biogrid data | tee $log_file.biogrid-load-output

(cd $SOURCES/biogrid
mv BIOGRID-* old/
wget http://thebiogrid.org/downloads/archives/Latest%20Release/BIOGRID-ORGANISM-LATEST.tab2.zip
unzip -q BIOGRID-ORGANISM-LATEST.tab2.zip
if [ ! -e BIOGRID-ORGANISM-Schizosaccharomyces_pombe-*.tab2.txt ]
then
  echo "no pombe BioGRID file found - exiting"
  exit 1
fi
) 2>&1 | tee -a $log_file.biogrid-load-output

cd $HOME/git/pombase-run

# see https://sourceforge.net/p/pombase/chado/61/
cat $SOURCES/biogrid/BIOGRID-ORGANISM-Schizosaccharomyces_pombe-*.tab2.txt | ./script/pombase-import.pl ./load-chado.yaml biogrid --use_first_with_id  --organism-taxonid-filter=4896 --interaction-note-filter="Contributed by PomBase|contributed by PomBase|triple mutant" --evidence-code-filter='Co-localization' $HOST $DB $USER $PASSWORD 2>&1 | tee -a $LOG_DIR/$log_file.biogrid-load-output

evidence_summary () {
  psql $DB -c "select count(feature_cvtermprop_id), value from feature_cvtermprop where type_id in (select cvterm_id from cvterm where name = 'evidence') group by value order by count(feature_cvtermprop_id)"
}

echo annotation evidence counts before loading
evidence_summary

echo starting import of GOA GAF data

{
for gaf_file in go_comp.txt go_proc.txt go_func.txt From_curation_tool GO_ORFeome_localizations2.txt
do
  echo reading $gaf_file
  ./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=PomBase $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/external-go-data/$gaf_file

  echo counts:
  evidence_summary
done

echo $SOURCES/sources/gene_association.pombase.inf.gaf
./script/pombase-import.pl ./load-chado.yaml gaf --term-id-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_GO_IDs --with-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=PomBase,GOC $HOST $DB $USER $PASSWORD < $SOURCES/go-svn/scratch/gaf-inference/gene_association.pombase.inf.gaf

echo counts after inf:
evidence_summary

echo $SOURCES/gene_association.goa_uniprot.pombe
CURRENT_GOA_GAF="$SOURCES/gene_association.goa_uniprot.gz"
DOWNLOADED_GOA_GAF=$CURRENT_GOA_GAF.downloaded
GET -i $CURRENT_GOA_GAF $GOA_GAF_URL > $DOWNLOADED_GOA_GAF
if [ -s $DOWNLOADED_GOA_GAF ]
then
  mv $DOWNLOADED_GOA_GAF $CURRENT_GOA_GAF
else
  echo "didn't download new $GOA_GAF_URL"
fi

gzip -d < $CURRENT_GOA_GAF | kgrep '\ttaxon:(4896|284812)\t' | ./script/pombase-import.pl ./load-chado.yaml gaf --use-only-first-with-id --taxon-filter=4896 --term-id-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_GO_IDs --with-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=InterPro,UniProtKB,UniProt $HOST $DB $USER $PASSWORD

} 2>&1 | tee $LOG_DIR/$log_file.gaf-load-output

echo annotation count after GAF loading:
evidence_summary


echo load quantitative gene expression data

for file in $SOURCES/pombe-embl/external_data/Quantitative_gene_expression_data/*
do
  echo loading: $file
  ./script/pombase-import.pl load-chado.yaml quantitative --organism_taxonid=4896 $HOST $DB $USER $PASSWORD < $file 2>&1
done | tee $LOG_DIR/$log_file.quantitative


echo phenotype data from PMID:23697806
./script/pombase-import.pl load-chado.yaml phenotype_annotation $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/phenotype_mapping/phaf_format_phenotypes.tsv 2>&1 | tee $LOG_DIR/$log_file.phenotypes_from_PMID_23697806
./script/pombase-import.pl load-chado.yaml phenotype_annotation $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/phenotype_mapping/HU_data_from_PMID_23697806 2>&1 | tee $LOG_DIR/$log_file.HU_phenotypes_from_PMID_23697806

for id in 18684775 19264558 21850271 22806344 23861937 23950735
do
  (echo phenotype data from PMID:$id; ./script/pombase-import.pl load-chado.yaml phenotype_annotation $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/external_data/phaf_files/chado_load/PMID_${id}_phaf.csv) 2>&1 | tee -a $LOG_DIR/$log_file.phenotypes_from_PMID_$id
done

echo load Compara orthologs

./script/pombase-import.pl load-chado.yaml orthologs --publication=PMID:19029536 --organism_1_taxonid=4896 --organism_2_taxonid=9606 --swap-direction $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/orthologs/compara_orths.tsv 2>&1 | tee $LOG_DIR/$log_file.compara_orths


echo load manual pombe to human orthologs: conserved_multi.txt

./script/pombase-import.pl load-chado.yaml orthologs --publication=PMID:19029536 --organism_1_taxonid=4896 --organism_2_taxonid=9606 --swap-direction $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/orthologs/conserved_multi.txt 2>&1 | tee $LOG_DIR/$log_file.manual_multi_orths

echo load manual pombe to human orthologs: conserved_one_to_one.txt

./script/pombase-import.pl load-chado.yaml orthologs --publication=PMID:19029536 --organism_1_taxonid=4896 --organism_2_taxonid=9606 --swap-direction --add_org_1_term_name='predominantly single copy (one to one)' --add_org_1_term_cv='species_dist' $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/orthologs/conserved_one_to_one.txt 2>&1 | tee $LOG_DIR/$log_file.manual_1-1_orths

FINAL_DB=$DB-l1

echo copying $DB to $FINAL_DB
createdb -T $DB $FINAL_DB

CURATION_TOOL_DATA=current-prod-dump.json
scp pomcur@pombe-prod:/var/pomcur/backups/$CURATION_TOOL_DATA .

./script/pombase-import.pl load-chado.yaml pomcur --organism-taxonid=4896 --db-prefix=PomBase $HOST $FINAL_DB $USER $PASSWORD < $CURATION_TOOL_DATA 2>&1 | tee $LOG_DIR/$log_file.curation_tool_data

echo annotation count after loading curation tool data:
evidence_summary

echo filtering redundant annotations
./script/pombase-process.pl ./load-chado.yaml go-filter $HOST $FINAL_DB $USER $PASSWORD

echo annotation count after filtering redundant annotations:
evidence_summary

echo running consistency checks
./script/check-chado.pl ./check-db.yaml $HOST $FINAL_DB $USER $PASSWORD

DUMP_DIR=/var/www/pombase/dumps/$FINAL_DB

mkdir $DUMP_DIR
mkdir $DUMP_DIR/logs

./script/pombase-export.pl ./load-chado.yaml gaf --organism-taxon-id=4896 $HOST $FINAL_DB $USER $PASSWORD > $DUMP_DIR/$FINAL_DB.gaf
./script/pombase-export.pl ./load-chado.yaml interactions --organism-taxon-id=4896 $HOST $FINAL_DB $USER $PASSWORD > $DUMP_DIR/$FINAL_DB.pombe-interactions.biogrid
./script/pombase-export.pl ./load-chado.yaml orthologs --organism-taxon-id=4896 --other-organism-taxon-id=9606 $HOST $FINAL_DB $USER $PASSWORD > $DUMP_DIR/$FINAL_DB.human-orthologs.txt
/var/pomcur/sources/go-svn/software/utilities/filter-gene-association.pl -e < $DUMP_DIR/$FINAL_DB.gaf > $LOG_DIR/$log_file.gaf-check

cp $LOG_DIR/$log_file.gaf-load-output $DUMP_DIR/logs/
cp $LOG_DIR/$log_file.biogrid-load-output $DUMP_DIR/logs/
cp $LOG_DIR/$log_file.gaf-check $DUMP_DIR/logs/$log_file.gaf-check
cp $LOG_DIR/$log_file.compara_orths $DUMP_DIR/logs/$log_file.compara-orth-load-output
cp $LOG_DIR/$log_file.manual_multi_orths $DUMP_DIR/logs/$log_file.manual-multi-orths-output
cp $LOG_DIR/$log_file.manual_1-1_orths $DUMP_DIR/logs/$log_file.manual-1-1-orths-output
cp $LOG_DIR/$log_file.curation_tool_data $DUMP_DIR/logs/$log_file.curation-tool-data-load-output
cp $LOG_DIR/$log_file.quantitative $DUMP_DIR/logs/$log_file.quantitative
cp $LOG_DIR/$log_file.phenotypes_from_* $DUMP_DIR/logs/

psql $FINAL_DB -c "select count(id), name from (select p.cvterm_id::text || '_cvterm' as id,
 substring(type.name from 'annotation_extension_relation-(.*)') as name from
 cvterm type, cvtermprop p where p.type_id = type.cvterm_id and type.name like
 'annotation_ex%' union all select r.cvterm_relationship_id::text ||
 '_cvterm_rel' as id, t.name as name from cvterm_relationship r, cvterm t where
 t.cvterm_id = type_id and r.subject_id in (select cvterm_id from cvterm, cv
 where cvterm.cv_id = cv.cv_id and cv.name = 'PomBase annotation extension terms')) 
 as sub group by name order by name;" > $DUMP_DIR/logs/$log_file.extension_relation_counts

(
psql $FINAL_DB -c "select count(distinct fc_id), cv_name from (select distinct
fc.feature_cvterm_id as fc_id, cv.name as cv_name from cvterm t,
feature_cvterm fc, cv where fc.cvterm_id = t.cvterm_id and cv.cv_id = t.cv_id
and cv.name <> 'PomBase annotation extension terms' UNION select distinct
fc.feature_cvterm_id as fc_id, parent_cv.name as cv_name from cvterm t,
feature_cvterm fc, cv term_cv, cvterm_relationship rel, cvterm parent_term, cv
parent_cv, cvterm rel_type where fc.cvterm_id = t.cvterm_id and term_cv.cv_id
= t.cv_id and t.cvterm_id = subject_id and parent_term.cvterm_id = object_id
and parent_term.cv_id = parent_cv.cv_id and term_cv.name = 'PomBase annotation extension terms' and rel.type_id = rel_type.cvterm_id and rel_type.name =
'is_a') as sub group by cv_name order by count;"
echo
echo total:
psql $FINAL_DB -c "select count(distinct fc_id) from (select distinct
fc.feature_cvterm_id as fc_id, cv.name as cv_name from cvterm t,
feature_cvterm fc, cv where fc.cvterm_id = t.cvterm_id and cv.cv_id = t.cv_id
and cv.name <> 'PomBase annotation extension terms' UNION select distinct
fc.feature_cvterm_id as fc_id, parent_cv.name as cv_name from cvterm t,
feature_cvterm fc, cv term_cv, cvterm_relationship rel, cvterm parent_term, cv
parent_cv, cvterm rel_type where fc.cvterm_id = t.cvterm_id and term_cv.cv_id
= t.cv_id and t.cvterm_id = subject_id and parent_term.cvterm_id = object_id
and parent_term.cv_id = parent_cv.cv_id and term_cv.name = 'PomBase annotation extension terms' and rel.type_id = rel_type.cvterm_id and rel_type.name =
'is_a') as sub;" ) > $DUMP_DIR/logs/$log_file.annotation_counts_by_cv


cp $LOG_DIR/*.txt $DUMP_DIR/logs/

mkdir $DUMP_DIR/pombe-embl
cp -r $SOURCES/pombe-embl/* $DUMP_DIR/pombe-embl/

psql $FINAL_DB -c 'grant select on all tables in schema public to public;'

DUMP_FILE=$DUMP_DIR/$FINAL_DB.dump.gz

echo dumping to $DUMP_FILE
pg_dump $FINAL_DB | gzip -9v > $DUMP_FILE

date
