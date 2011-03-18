use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'PomBase',
    license             => 'perl',
    dist_author         => q{Kim Rutherford <kmr44@cam.ac.uk>},
    dist_version_from   => 'lib/PomBase.pm',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'PomBase-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
