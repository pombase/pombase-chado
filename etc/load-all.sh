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
) 2>&1 | tee -a $log_file.biogrid

cd $HOME/git/pombase-run
cat $SOURCES/biogrid/BIOGRID-ORGANISM-Schizosaccharomyces_pombe-*.tab2.txt | ./script/pombase-import.pl ./load-chado.yaml biogrid $HOST $DB $USER $PASSWORD 2>&1 | tee -a $LOG_DIR/$log_file.biogrid

echo starting import of GOA GAF data 1>&2

(
echo $HOME/Work/pombe/pombe-embl/external-go-data/go_comp.tex
./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/go_comp.tex 
echo $HOME/Work/pombe/pombe-embl/external-go-data/go_proc.tex
./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/go_proc.tex
echo $HOME/Work/pombe/pombe-embl/external-go-data/go_func.tex
./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/go_func.tex
echo $HOME/Work/pombe/sources/gene_association.GeneDB_Spombe.inf.gaf
./script/pombase-import.pl ./load-chado.yaml gaf --term-id-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_GO_IDs --with-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $SOURCES/go/scratch/gaf-inference/gene_association.pombase.inf.gaf
echo $HOME/Work/pombe/pombe-embl/external-go-data/From_curation_tool
./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/From_curation_tool
echo $HOME/Work/pombe/pombe-embl/external-go-data/GO_ORFeome_localizations2.tex
./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/GO_ORFeome_localizations2.tex
echo $SOURCES/gene_association.goa_uniprot.pombe
./script/pombase-import.pl ./load-chado.yaml gaf --term-id-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_GO_IDs --with-filter-filename=$SOURCES/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=InterPro,UniProtKB $HOST $DB $USER $PASSWORD < $SOURCES/gene_association.goa_uniprot.pombe

) 2>&1 | tee $LOG_DIR/$log_file.gaf

echo load Compara orthologs 1>&2

./script/pombase-import.pl load-chado.yaml orthologs --publication=PMID:19029536 --organism_1_taxonid=4896 --organism_2_taxonid=9606 --swap-direction $HOST $DB $USER $PASSWORD < $SOURCES/pombe-embl/orthologs/compara_orths.tsv

echo copying $DB to $DB-l1
createdb -T $DB $DB-l1

CURATION_TOOL_DATA=current-prod-dump.json
scp pomcur@pombe-prod:/var/pomcur/backups/$CURATION_TOOL_DATA .

./script/pombase-import.pl load-chado.yaml pomcur $HOST $DB-l1 $USER $PASSWORD < $CURATION_TOOL_DATA

echo filtering redundant terms 1>&2

./script/pombase-process.pl ./load-chado.yaml go-filter $HOST $DB-l1 $USER $PASSWORD

echo running consistency checks
./script/check-chado.pl ./check-db.yaml $HOST $DB-l1 $USER $PASSWORD
