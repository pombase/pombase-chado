package MooseX::QuietCarping;
# from: http://stackoverflow.com/questions/6171255/useful-errors-for-moose-and-moosexdeclare

# Not actually a Moose thing, but helpful for Moose.
# calm Moose-internal stacktraces down a little
use Carp;

my %retain = ();
sub import {
    my $class = shift;
    $retain{$_}++ for @_;
}

CHECK {
    for (sort keys %INC) {
    s{\.pm$}{};
    s{[/\\]}{::}g; # CROSS PLATFORM MY ARSE
    next if $retain{$_};
    $Carp::Internal{$_}++ if /^(?:Class::MOP|Moose|MooseX)\b/
    }
    %retain = (); # don't need this no more
}

1;
