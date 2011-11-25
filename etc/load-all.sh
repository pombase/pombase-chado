#!/bin/sh -

# run script/make-db first

HOST=$1
DB=$2
USER=$3
PASSWORD=$4

cd $HOME/pombe/pombe-embl/
svn update || exit 1

cd $HOME/git/pombase-run
git pull || exit 1

export PERL5LIB=$HOME/git/pombase-run/lib

cd $HOME/chado/embl_load
log_file=log.`date_string`
$HOME/git/pombase-run/script/load-chado.pl --mapping "pt_mod:PSI-MOD:$HOME/Dropbox/pombase/ontologies/PSI-MOD/modification_map.txt" --mapping "phenotype:fission_yeast_phenotype:$HOME/Dropbox/pombase/ontologies/phenotype/phenotype-map.txt" --obsolete-term-map $HOME/pombe/go-doc/obsoletes-exact $HOME/git/pombase-run/load-chado.yaml $HOST $DB $USER $PASSWORD $HOME/pombe/pombe-embl/*.contig 2>&1 | tee $log_file
$HOME/git/pombase-run/etc/process-log.pl $log_file

echo starting import of biogrid data 1>&2

cd $HOME/git/pombase-run
./script/pombase-import.pl ./load-chado.yaml biogrid $HOST $DB $USER $PASSWORD < $HOME/downloads/BIOGRID-ORGANISM-Schizosaccharomyces_pombe-3.1.78.tab2.txt

echo starting import of GOA GAF data 1>&2

./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/go_comp.tex
./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/go_proc.tex
./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/go_func.tex
./script/pombase-import.pl ./load-chado.yaml gaf --term-id-filter-filename=$HOME/pombe/pombe-embl/goa-load-fixes/filtered_GO_IDs --db-ref-filter-filename=$HOME/pombe/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/sources/gene_association.GeneDB_Spombe.inf.gaf
./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/From_curation_tool
./script/pombase-import.pl ./load-chado.yaml gaf --assigned-by-filter=GeneDB_Spombe $HOST $DB $USER $PASSWORD < $HOME/Work/pombe/pombe-embl/external-go-data/GO_ORFeome_localizations2.tex
./script/pombase-import.pl ./load-chado.yaml gaf --term-id-filter-filename=$HOME/pombe/pombe-embl/goa-load-fixes/filtered_GO_IDs --db-ref-filter-filename=$HOME/pombe/pombe-embl/goa-load-fixes/filtered_mappings --assigned-by-filter=InterPro,UniProtKB $HOST $DB $USER $PASSWORD < ~/Work/pombe/gene_association.goa_uniprot.pombe


echo filtering redundant terms 1>&2

./script/pombase-process.pl ./load-chado.yaml go-filter $HOST $DB $USER $PASSWORD
