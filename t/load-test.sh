#!/bin/sh

#CARP=-MCarp::Always
CARP=

cd data
PERL5LIB=../lib time perl $CARP ../script/load-chado.pl -d -t $* \
  --mapping "sequence_feature:sequence:$HOME/Dropbox/pombase/ontologies/SO/features-to-so_mapping_only.txt" \
  --mapping "pt_mod:PSI-MOD:$HOME/Dropbox/pombase/ontologies/PSI-MOD/modification_map.txt" \
  --mapping "phenotype:fission_yeast_phenotype:$HOME/Dropbox/pombase/ontologies/phenotype/phenotype-map.txt" \
  --obsolete-term-map ~/pombe/go-doc/obsoletes-exact ../load-chado.yaml localhost `cat /tmp/new_test_db` kmr44 kmr44 chromosome1.contig.embl 2>&1 | cut -c1-300
