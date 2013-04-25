#!/bin/bash -

# run script/make-db first

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
  --mapping "sequence_feature:sequence:$HOME/Dropbox/pombase/ontologies/SO/features-to-so_mapping_only.txt" \
  --mapping "pt_mod:PSI-MOD:$HOME/Dropbox/pombase/ontologies/PSI-MOD/modification_map.txt" \
  --mapping "phenotype:fission_yeast_phenotype:$HOME/Dropbox/pombase/ontologies/phenotype/phenotype-map.txt" \
  --obsolete-term-map $HOME/pombe/go-doc/obsoletes-exact $HOME/git/pombase-run/load-chado.yaml \
  $HOST $DB $USER $PASSWORD $SOURCES/pombe-embl/*.contig 2>&1 | tee $log_file || exit 1

$HOME/git/pombase-run/etc/process-log.pl $log_file

echo starting import of biogrid data | tee $log_file.biogrid

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
cat $SOURCES/biogrid/BIOGRID-ORGANISM-Schizosaccharomyces_pombe-*.tab2.txt | ./script/pombase-import.pl ./load-chado.yaml biogrid $HOST $DB $USER $PASSWORD 2>&1 | tee -a $LOG_DIR/$log_file.biogrid

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
./script/pombase-import.pl ./load-chado.yaml gaf --term-id-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_GO_IDs --with-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=PomBase $HOST $DB $USER $PASSWORD < $SOURCES/go-svn/scratch/gaf-inference/gene_association.pombase.inf.gaf

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

gzip -d < $CURRENT_GOA_GAF | kgrep '\ttaxon:(4896|284812)\t' | ./script/pombase-import.pl ./load-chado.yaml gaf --taxon-filter=4896 --term-id-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_GO_IDs --with-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=InterPro,UniProtKB $HOST $DB $USER $PASSWORD

} 2>&1 | tee $LOG_DIR/$log_file.gaf-load-output

echo annotation count after GAF loading:
evidence_summary


echo load quantitative gene expression data

for file in /var/pomcur/sources/quantitative_gene_expression/*
do
  echo loading: $file
  ./script/pombase-import.pl load-chado.yaml quantitative --organism_taxonid=4896 $HOST $DB $USER $PASSWORD < $file 2>&1
done | tee $LOG_DIR/$log_file.quantitative


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

./script/pombase-import.pl load-chado.yaml pomcur $HOST $FINAL_DB $USER $PASSWORD < $CURATION_TOOL_DATA 2>&1 | tee $LOG_DIR/$log_file.curation_tool_data

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
mkdir $DUMP_DIR/warnings

./script/pombase-export.pl ./load-chado.yaml gaf --organism-taxon-id=4896 $HOST $FINAL_DB $USER $PASSWORD > $DUMP_DIR/$FINAL_DB.gaf
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

cp $LOG_DIR/*.txt $DUMP_DIR/warnings/

mkdir $DUMP_DIR/pombe-embl
cp -r $SOURCES/pombe-embl/* $DUMP_DIR/pombe-embl/

psql $FINAL_DB -c 'grant select on all tables in schema public to public;'

DUMP_FILE=$DUMP_DIR/$FINAL_DB.dump.gz

echo dumping to $DUMP_FILE
pg_dump $FINAL_DB | gzip -9v > $DUMP_FILE
