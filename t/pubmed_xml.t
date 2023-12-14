use strict;
use warnings;
use Test::More tests => 3;

use Storable qw(thaw);

BEGIN {
  unshift @INC, 't', 'lib';
}

use GDBM_File;
use PomBase::TestUtil;
use PomBase::Chado::PubmedUtil;

my $test_util = PomBase::TestUtil->new();
my $config = $test_util->config();

local $/ = undef;

open my $f, '<', 'data/pubmed_37189341.xml' or die;

my $xml = <$f>;

unlink '/tmp/pubmed_cache.gdbm';

tie my %pubmed_cache, 'GDBM_File', '/tmp/pubmed_cache.gdbm', &GDBM_WRCREAT, 0640;

my $pubmed_util = PomBase::Chado::PubmedUtil->new(chado => $test_util->chado(),
                                                  config => $config,
                                                  pubmed_cache => \%pubmed_cache);
$pubmed_util->parse_pubmed_xml($xml);

ok(exists $pubmed_cache{'PMID:37189341'});

my $pub_details = thaw($pubmed_cache{'PMID:37189341'});

is($pub_details->{publication_date}, '25 Mar 2023');

ok(grep { $_ eq 'Clr4' } @{$pub_details->{keywords}});
