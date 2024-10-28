use strict;
use warnings;

use lib 'lib';
use feature qw(say);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use File::Basename;
use Test::More;

use utf8;

# nicer output for diag and failures, see
# http://perldoc.perl.org/Test/More.html#CAVEATS-and-NOTES
my $builder = Test::More->builder;
binmode $builder->output,         ":encoding(UTF-8)";
binmode $builder->failure_output, ":encoding(UTF-8)";
binmode $builder->todo_output,    ":encoding(UTF-8)";

my $af_path = dirname(__FILE__) . '/../../address-formatting';
my $verbose = 0;

my $conf_path = $af_path . '/conf/';

my $CLASS = 'Geo::Address::Formatter';
use_ok($CLASS);

my $GAF = $CLASS->new(conf_path => $conf_path);

{
    # is the correct abbreviation set?
    my %input = (
        "city"         => "Berlin",
        "country"      => "Deutschland",
        "country_code" => "de",
        "road"         => "Platz der Republic",
        "state"        => "Berlin",
    );

    my $formatted = $GAF->format_address(\%input, { abbreviate => 1 });
    $formatted =~ s/\n/, /g;
    $formatted =~ s/, $//g;
    
    is ($formatted, 'Pl der Republic, Berlin, Deutschland', 'correct abbreviated formatted' )
}


#{
#    # is the correct abbreviation set?
#    my %input = (
#        "city"         => "München",
#        "country"      => "Deutschland",
#        "country_code" => "de",
#        "house_number" => "6",
#        "postcode"     => "81829",
#        "road"         => "Willy-Brandt-Platz",
#        "state"        => "Bayern",
#    );
#
#    my $formatted = $GAF->format_address(\%input, { abbreviate => 1 });
#    $formatted =~ s/\n/, /g;
#    $formatted =~ s/, $//g;    
#    is ($formatted, 'Willy-Brandt-Platz 6, 81829 München, Deutschland', 'correct abbreviated formatted')
#}


done_testing();

1;
