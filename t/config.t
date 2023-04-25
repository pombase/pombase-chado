use strict;
use warnings;
use Test::More tests => 8;

use PomBase::TestUtil;
use PomBase::Config;

my $test_util = PomBase::TestUtil->new();

my $config = $test_util->config();

is ($config->{evidence_types}->{'microscopy'}->{name}, 'microscopy evidence');
is ($config->{evidence_types}->{'Microscopy'}->{name}, 'microscopy evidence');
is ($config->{evidence_types}->{'ECO:0001098'}->{name}, 'microscopy evidence');
is ($config->{evidence_types}->{'Synthetic Haploinsufficiency'}->{name}, 'Synthetic Haploinsufficiency');
is ($config->{evidence_types}->{'synthetic haploinsufficiency'}->{name}, 'Synthetic Haploinsufficiency');
ok (!defined $config->{evidence_types}->{'dummy'});
is ($config->{evidence_types}->{'ECO:0000337'}->{name}, 'gel electrophoresis evidence');
is ($config->{evidence_types}->{'eco:0000337'}->{name}, 'gel electrophoresis evidence');

is ($config->{evidence_name_to_code}->{'gel electrophoresis evidence'}, 'ECO:0000337');
