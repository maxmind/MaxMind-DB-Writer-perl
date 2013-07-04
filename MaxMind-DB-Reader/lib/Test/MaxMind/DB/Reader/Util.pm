package Test::MaxMind::DB::Reader::Util;

use Sub::Exporter -setup => { exports => ['standard_metadata'] };

sub standard_metadata {
    return (
        database_type => 'Test',
        languages     => [ 'en', 'zh' ],
        description   => {
            en => 'Test Database',
            zh => 'Test Database Chinese',
        },
    );
}

1;
