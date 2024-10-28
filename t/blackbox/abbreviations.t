use strict;
use warnings;

use lib 'lib';
use feature qw(say);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use File::Basename;
use File::Find::Rule;
use File::Slurper 'read_text';
use File::Spec;
use Getopt::Long;
use Test::Exception;
use Test::More;
use YAML::XS qw(LoadFile);
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

# first a basic test to ensure abbreviation is working
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

# now let's check the files
my $path = $af_path . '/testcases/';
my $input_country;

GetOptions(
    'country:s' => \$input_country,
    'verbose'   => \$verbose,
);
if ($input_country) {
    $input_country = lc($input_country);
}

ok(1);

if (-d $path){

    my $CLASS = 'Geo::Address::Formatter';
    use_ok($CLASS);

    my $conf_path = $af_path . '/conf/';
    my $GAF       = $CLASS->new(conf_path => $conf_path);

    # ok, time to actually run the country tests
    sub _one_testcase {
        my $country     = shift;
        my $rh_testcase = shift;

        my $expected = $rh_testcase->{expected};
        my $actual   = $GAF->format_address($rh_testcase->{components}, { abbreviate => 1 });

        if (0) { # turn on for char by char comparison
            my @e = (split //, $expected);
            my @a = (split //, $actual);
            my $c = 0;
            foreach my $char (@e) {
                if ($e[$c] eq $a[$c]) {
                    warn "same $c same $a[$c]";
                } else {
                    warn "not same $c " . $e[$c] . ' ' . $a[$c] . "\n";
                }
                $c++;
            }
        }
        is($actual, $expected, $country . ' - ' . ($rh_testcase->{description} || 'no description set'));
    }

    # get list of country specific tests
    my @files = File::Find::Rule->file()->name('*.yaml')->in($path);
    foreach my $filename (sort @files) {
        next if ($filename !~ m/abbreviations/);  # others tested by countries.t
        my $country = basename($filename);
        $country =~ s/\.\w+$//; # us.yaml => us

        if (defined($input_country) && $input_country) {
            if ($country ne $input_country) {
                if ($verbose) {
                    warn "skipping $country tests";
                }
                next;
            }
        }

        my @a_testcases = ();
        lives_ok {
            @a_testcases = LoadFile($filename);
        }
        "parsing file $filename";

        foreach my $rh_testcase (@a_testcases) {
            _one_testcase($country, $rh_testcase);
        }
    }
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