use strict;
use warnings;
use Test::More tests => 1;

package Test;
use Moose;
use perl5i::2;

with 'PomBase::Role::CvQuery';
with 'PomBase::Role::ChadoUser';

func test
{

}

no Moose;

package main;
