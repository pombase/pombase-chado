#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'PomBase' ) || print "Bail out!
";
}

diag( "Testing PomBase $PomBase::VERSION, Perl $], $^X" );
