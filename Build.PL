use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name => 'Dancer::Plugin::Catmandu::OAI',
    license => 'perl',
    dist_author => [
        'Nicolas Steenlant <nicolas.steenlant@ugent.be>',
        'Nicolas Franck <nicolas.franck@ugent.be>'
    ],
    build_requires => {
        'Software::License' => 0,
        'Test::Exception' => 0,
        'Test::More' => 0,
    },
    requires => {
        'perl' => '5.10.1',
        'Catmandu' => '0.8013',
        'Catmandu::Exporter::Template' => 'v0.02',
        'Dancer' => '1.3121',
        'DateTime' => 0,
        'Clone' => 0
    },
    add_to_cleanup => [qw(
        Dancer-Plugin-Catmandu-OAI-*
    )],
    create_makefile_pl => 'traditional',
    create_license => 1,
);

$builder->create_build_script;
