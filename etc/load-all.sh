#!/bin/bash -

# run script/make-db first

set -o pipefail

HOST=$1
DB=$2
USER=$3
PASSWORD=$4

LOG_DIR=`pwd`

SOURCES=/var/pomcur/sources

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
  $HOST $DB $USER $PASSWORD $SOURCES/pombe-embl/*.contig 2>&1 | tee $log_file || (echo exiting after failure; exit 1)

$HOME/git/pombase-run/etc/process-log.pl $log_file

echo starting import of biogrid data | tee $log_file.biogrid

(cd $SOURCES/biogrid
mv BIOGRID-* old/
wget http://thebiogrid.org/downloads/archives/Latest%20Release/BIOGRID-ORGANISM-LATEST.tab2.zip
unzip -q BIOGRID-ORGANISM-LATEST.tab2.zip
if [ ! -e BIOGRID-ORGANISM-Schizosaccharomyces_pombe-*.tab2.txt ]
then
  echo "no pombe BioGRID file found - exiting" 1>&2
  exit 1
fi
) 2>&1 | tee -a $log_file.biogrid-output

cd $HOME/git/pombase-run
cat $SOURCES/biogrid/BIOGRID-ORGANISM-Schizosaccharomyces_pombe-*.tab2.txt | ./script/pombase-import.pl ./load-chado.yaml biogrid $HOST $DB $USER $PASSWORD 2>&1 | tee -a $LOG_DIR/$log_file.biogrid

echo starting import of GOA GAF data 1>&2

(
for gaf_file in go_comp.txt go_proc.txt go_func.txt From_curation_tool GO_ORFeome_localizations2.txt
do
  echo reading $gaf_file
  ./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/external-go-data/$gaf_file
done

echo $SOURCES/sources/gene_association.GeneDB_Spombe.inf.gaf
./script/pombase-import.pl ./load-chado.yaml gaf --term-id-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_GO_IDs --with-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $SOURCES/go/scratch/gaf-inference/gene_association.pombase.inf.gaf

echo $SOURCES/gene_association.goa_uniprot.pombe
./script/pombase-import.pl ./load-chado.yaml gaf --term-id-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_GO_IDs --with-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=InterPro,UniProtKB $HOST $DB $USER $PASSWORD < $SOURCES/gene_association.goa_uniprot.pombe

) 2>&1 | tee $LOG_DIR/$log_file.gaf-load-output

echo load Compara orthologs 1>&2

./script/pombase-import.pl load-chado.yaml orthologs --publication=PMID:19029536 --organism_1_taxonid=4896 --organism_2_taxonid=9606 --swap-direction $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/orthologs/compara_orths.tsv 2>&1 | tee $LOG_DIR/$log_file.compara_orths


echo load manual pombe to human orthologs: conserved_multi.txt 1>&2

./script/pombase-import.pl load-chado.yaml orthologs --publication=PMID:19029536 --organism_1_taxonid=4896 --organism_2_taxonid=9606 --swap-direction $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/orthologs/conserved_multi.txt 2>&1 | tee $LOG_DIR/$log_file.manual_multi_orths

echo load manual pombe to human orthologs: conserved_one_to_one.txt 1>&2

./script/pombase-import.pl load-chado.yaml orthologs --publication=PMID:19029536 --organism_1_taxonid=4896 --organism_2_taxonid=9606 --swap-direction --add_org_1_term_name='predominantly single copy (one to one)' --add_org_1_term_cv='species_dist' $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/orthologs/conserved_one_to_one.txt 2>&1 | tee $LOG_DIR/$log_file.manual_1-1_orths

FINAL_DB=$DB-l1

echo copying $DB to $FINAL_DB
createdb -T $DB $FINAL_DB

CURATION_TOOL_DATA=current-prod-dump.json
scp pomcur@pombe-prod:/var/pomcur/backups/$CURATION_TOOL_DATA .

./script/pombase-import.pl load-chado.yaml pomcur $HOST $FINAL_DB $USER $PASSWORD < $CURATION_TOOL_DATA 2>&1 | tee $LOG_DIR/$log_file.curation_tool_data

echo filtering redundant terms 1>&2

./script/pombase-process.pl ./load-chado.yaml go-filter $HOST $FINAL_DB $USER $PASSWORD

echo running consistency checks
./script/check-chado.pl ./check-db.yaml $HOST $FINAL_DB $USER $PASSWORD

DUMP_DIR=/var/www/pombase/kmr44/dumps/

mkdir $DUMP_DIR/$FINAL_DB

./script/pombase-export.pl ./load-chado.yaml gaf --organism-taxon-id=4896 $HOST $FINAL_DB $USER $PASSWORD > $DUMP_DIR/$FINAL_DB/$FINAL_DB.gaf
./script/pombase-export.pl ./load-chado.yaml orthologs --organism-taxon-id=4896 --other-organism-taxon-id=9606 $HOST $FINAL_DB $USER $PASSWORD > $DUMP_DIR/$FINAL_DB/$FINAL_DB.human-orthologs.txt
/var/pomcur/sources/go/software/utilities/filter-gene-association.pl -e < $DUMP_DIR/$FINAL_DB/$FINAL_DB.gaf > $LOG_DIR/$log_file.gaf-check 2>&1

cp $LOG_DIR/$log_file.gaf-load-output $DUMP_DIR/$FINAL_DB/
cp $LOG_DIR/$log_file.biogrid-load-output $DUMP_DIR/$FINAL_DB/
cp $LOG_DIR/$log_file.gaf-check $DUMP_DIR/$FINAL_DB/$log_file.gaf-check
cp $LOG_DIR/$log_file.compara_orths $DUMP_DIR/$FINAL_DB/$log_file.compara-orth-load-output
cp $LOG_DIR/$log_file.manual_multi_orths $DUMP_DIR/$FINAL_DB/$log_file.manual-multi-orths-output
cp $LOG_DIR/$log_file.manual_1-1_orths $DUMP_DIR/$FINAL_DB/$log_file.manual-1-1-orths-output
cp $LOG_DIR/$log_file.curation_tool_data $DUMP_DIR/$FINAL_DB/$log_file.curation-tool-data-load-output
cp $LOG_DIR/*.txt $DUMP_DIR/$FINAL_DB/
mkdir $DUMP_DIR/$FINAL_DB/pombe-embl
cp -r $SOURCES/pombe-embl/* $DUMP_DIR/$FINAL_DB/pombe-embl/

psql $FINAL_DB -c 'grant select on all tables in schema public to public;'

DUMP_FILE=$DUMP_DIR/$FINAL_DB/$FINAL_DB.dump.gz

echo dumping to $DUMP_FILE
pg_dump $FINAL_DB | gzip -9v > $DUMP_FILE
