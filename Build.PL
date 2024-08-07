use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'PomBase',
    license             => 'perl',
    dist_author         => q{Kim Rutherford <kmr44@cam.ac.uk>},
    dist_version_from   => 'lib/PomBase.pm',
    requires            => {
      perl                     => '5.12.0',
      'Bio::Chado::Schema'     => 0,
      'Bio::SeqIO'             => 0,
      'Bio::Tools::CodonOptTable' => 0,
      'Carp::Assert'           => 0,
      'DBIx::Class'            => 0,
      'Digest::MD5'            => 0,
      'File::Temp'             => 0,
      'IO::Handle'             => 0,
      'JSON'                   => 0,
      'Iterator::Simple'       => 0,
      'Memoize'                => 0,
      'Module::Find'           => 0,
      'Moose'                  => 0,
      'MooseX::Traits'         => 0,
      'Text::CSV'              => 0,
      'YAML'                   => 0,
      'YAML::Any'              => 0,
      'Text::Trim'             => 0,
      'Capture::Tiny'          => 0,
      'Scalar::Util'           => 0,
      'Clone'                  => 0,
      'utf8::all'              => 0,
      'Bio::Tools::CodonOptTable' => 0,
      'Data::Compare' => 0,
      'Tie::IxHash' => 0,
      'List::Util' => 1.63,
    },
    test_requires => {
      'Test::LongString' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'PomBase-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
