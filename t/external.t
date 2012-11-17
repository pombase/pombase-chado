use strict;
use warnings;
use Test::More tests => 1;

use PomBase::TestUtil;
use PomBase::External;

use YAML qw(LoadFile);

my $config = LoadFile('load-chado.yaml');

my @genes = PomBase::External::get_genes($config, 'Homo sapiens');

warn "---------\n";

@genes = PomBase::External::get_genes($config, 'Saccharomyces cerevisiae');
