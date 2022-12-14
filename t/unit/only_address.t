use strict;
use warnings;
use lib 'lib';
use Test::More;
use Test::Warn;
use File::Basename qw(dirname);
use utf8;

my $CLASS = 'Geo::Address::Formatter';
use_ok($CLASS);

my $af_path   = dirname(__FILE__) . '/../../address-formatting';
my $conf_path = $af_path . '/conf/';

my $GAF  = $CLASS->new(conf_path => $conf_path, only_address => 1, debug => 0);

{
    my $rh_components = {
      "borough" => "Friedrichshain-Kreuzberg",
      "city" => "Berlin",
      "country" => "Deutschland",
      "country_code" => "de",
      "fast_food" => "Burger Vision",
      "house_number" => "57",
      "postcode" => "10243",
      "road" =>  "Warschauer Straße",
      "state" =>  "Berlin",
      "suburb" =>  "Friedrichshain"
    };

    my $formatted = $GAF->format_address($rh_components);
    $formatted =~ s/\n$//g;  # remove from end
    $formatted =~ s/\n/, /g; # turn into commas
    is($formatted, 'Warschauer Straße 57, 10243 Berlin, Deutschland', 'correctly formatted with only address');
}

done_testing;

1;

