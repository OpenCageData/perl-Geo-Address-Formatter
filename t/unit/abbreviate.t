use strict;
use lib 'lib';
use Test::More;
use Test::Warn;
use Clone qw(clone);
use File::Basename qw(dirname);
use Data::Dumper;
use Text::Hogan::Compiler;

my $CLASS = 'Geo::Address::Formatter';
use_ok($CLASS);

my $path = dirname(__FILE__) . '/test_conf-abbreviate';
my $GAF = $CLASS->new( conf_path => $path );

{
    my $rh_components = {
        'country_code'  => 'US',
        'house_number'  => '301',
        'road'          => 'Hamilton Avenue',
        'neighbourhood' => 'Crescent Park',
        'city'          => 'Palo Alto',
        'postcode'      => '94303',
        'county'        => 'Santa Clara County',
        'state'         => 'California',
        'country'       => 'United States',
    };

    my $rh_new_comp = $GAF->_abbreviate($rh_components);
    is(
      $rh_new_comp->{road},
      'Hamilton Ave',
      'correctly abbreviated ' . $rh_components->{road}
    );
}

{
    my $rh_components = {
        'country_code'  => 'US',
        'house_number'  => '301',
        'road'          => 'Northwestern University Road',
        'neighbourhood' => 'Crescent Park',
        'city'          => 'Palo Alto',
        'postcode'      => '94303',
        'county'        => 'Santa Clara County',
        'state'         => 'California',
        'country'       => 'United States',
    };

    my $rh_new_comp = $GAF->_abbreviate($rh_components);
    is(
      $rh_new_comp->{road},
      'Northwestern University Rd',
      'correctly abbreviated ' . $rh_components->{road}
    );
}

{
    my $rh_components = {
        'country_code'  => 'US',
        'house_number'  => '301',
        'road'          => 'Hamilton Avenue',
        'neighbourhood' => 'Crescent Park',
        'city'          => 'Palo Alto',
        'postcode'      => '94303',
        'county'        => 'Santa Clara County',
        'state'         => 'California',
        'country'       => 'United States',
    };
    my $out = 
        $GAF->format_address($rh_components,{country => 'US', abbreviate => 1});
    is($out,
       '301 Hamilton Ave
Palo Alto, CA 94303
USA
',
       'correctly formatted and abbreviated components'
    );

}

done_testing();
