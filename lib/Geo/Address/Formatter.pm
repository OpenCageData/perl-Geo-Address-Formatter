# ABSTRACT: take structured address data and format it according to the various global/country rules

package Geo::Address::Formatter;

use strict;
use warnings;

use Clone qw(clone);
use Data::Dumper;
use File::Basename qw(dirname);
use File::Find::Rule;
use List::Util qw(first);
use Scalar::Util qw(looks_like_number);
use Text::Hogan::Compiler;
use Try::Tiny;
use YAML qw(Load LoadFile);
use utf8;

my $THC = Text::Hogan::Compiler->new;
my %THT_cache; # a place to store Text::Hogan::Template objects

=head1 DESCRIPTION

You have a structured postal address (hash) and need to convert it into a
readable address based on the format of the address country.

For example, you have:

  {
    house_number => 12,
    street => 'Avenue Road',
    postcode => 45678,
    city => 'Deville'
  }

you need:

  Great Britain: 12 Avenue Road, Deville 45678  
  France: 12 Avenue Road, 45678 Deville
  Germany: Avenue Road 12, 45678 Deville
  Latvia: Avenue Road 12, Deville, 45678

It gets more complicated with 100 countries and dozens more address
components to consider.

This module comes with a minimal configuration to run tests. Instead of
developing your own configuration please use (and contribute to)
those in https://github.com/lokku/address-formatting 
which includes test cases. 

Together we can address the world!

=head1 SYNOPSIS

  #
  # get the templates (or use your own) 
  # git clone git@github.com:lokku/address-formatting.git
  # 
  my $GAF = Geo::Address::Formatter->new( conf_path => '/path/to/templates' );
  my $components = { ... }
  my $text = $GAF->format_address($components, { country => 'FR' } );

=method new

  my $GAF = Geo::Address::Formatter->new( conf_path => '/path/to/templates' );

Returns one instance. The conf_path is required.

=cut

sub new {
    my ($class, %params) = @_;
    
    my $self = {};
    my $conf_path = $params{conf_path} || die "no conf_path set";
    bless( $self, $class );
    
    $self->_read_configuration($conf_path);
    return $self;
}

sub _read_configuration {
    my $self = shift;
    my $path = shift;

    my @a_filenames = 
        File::Find::Rule->file()->name( '*.yaml' )->in($path.'/countries');

    $self->{templates} = {};
    $self->{component_aliases} = {};

    # read the config file(s)
    foreach my $filename ( sort @a_filenames ){
        try {
            my $rh_templates = LoadFile($filename);

            # if file 00-default.yaml defines 'DE' (Germany) and
            # file 01-germany.yaml does as well, then the second
            # occurance of the key overwrites the first.
            foreach ( keys %$rh_templates ){
                $self->{templates}{$_} = $rh_templates->{$_};
            }
        }
        catch {
            warn "error parsing country configuration in $filename: $_";
        };
    }

    # see if we can load the components
    try {
        my @c = LoadFile($path . '/components.yaml');

        foreach my $rh_c (@c){
            if (defined($rh_c->{aliases})){
                foreach my $alias (@{$rh_c->{aliases}}){
                    $self->{component_aliases}{$alias} = $rh_c->{name};
                }
            }
        }
        $self->{ordered_components} = 
            [ map { $_->{name} => ($_->{aliases} ? @{$_->{aliases}} : ()) } @c];
    }
    catch {
        warn "error parsing component configuration: $_";
    };

    # get the state codes
    $self->{state_codes} = {};
    if ( -e $path . '/state_codes.yaml'){
        try {
            my $rh_c = LoadFile($path . '/state_codes.yaml');
            $self->{state_codes} = $rh_c;
        }
        catch {
            warn "error parsing component configuration: $_";
        };
    }
    return;
}

=head2 format_address

  my $text = $GAF->format_address(\%components, \%options );

Given a structures address (hashref) and options (hashref) returns a
formatted address.

The only option you can set currently is 'country' which should
be an uppercase ISO 3166-1 alpha-2 code, e.g. 'GB' for Great Britain.
If ommited we try to find the country in the address components.

=cut

sub format_address {
    my $self       = shift;
    my $rh_components = clone(shift) || return;
    my $rh_options = shift || {};

    my $cc = $rh_options->{country} 
            || $self->_determine_country_code($rh_components) 
            || '';

    if ($cc){
	$rh_components->{country_code} = $cc;
    } 

    #warn Dumper $rh_components;

    # set the aliases, unless this would overwrite something
    foreach my $alias (sort keys %{$self->{component_aliases}}){

        if (defined($rh_components->{$alias})
            && !defined($rh_components->{$self->{component_aliases}->{$alias}})
        ){     
            $rh_components->{$self->{component_aliases}->{$alias}} = 
                $rh_components->{$alias};
        }
    }

    $self->_sanity_cleaning($rh_components); 

    # determine the template
    my $rh_config = $self->{templates}{uc($cc)} || $self->{templates}{default};
    my $template_text = $rh_config->{address_template};

    #print STDERR "cc $cc\n";
    #print STDERR "comp " . Dumper $rh_components;

    # do we have the minimal components for an address?
    # or should we instead use the fallback template?
    if (!$self->_minimal_components($rh_components)){
        if (defined($rh_config->{fallback_template})){
            $template_text = $rh_config->{fallback_template};
        }
        elsif (defined($self->{templates}{default}{fallback_template})){
            $template_text = $self->{templates}{default}{fallback_template};
        }
        # no fallback
    }
    $template_text =~ s/\n/, /sg;

    # clean up the components
    $self->_fix_country($rh_components);
    $self->_apply_replacements($rh_components, $rh_config->{replace});
    $self->_add_state_code($rh_components);

    # add the attention, but only if needed
    my $ra_unknown = $self->_find_unknown_components($rh_components);
    if (scalar(@$ra_unknown)){
        $rh_components->{attention} = join(', ', map { $rh_components->{$_} } @$ra_unknown);
    }
    #warn Dumper $rh_components;

    # get a compiled template
    if (!defined($THT_cache{$template_text})){
        $THT_cache{$template_text} = $THC->compile($template_text, {'numeric_string_as_string' => 1});
    } 
    my $compiled_template = $THT_cache{$template_text};

    # render it
    my $text = $self->_render_template($compiled_template, $rh_components);
    $text = $self->_postformat($text,$rh_config->{postformat_replace});
    $text = $self->_clean($text);
    return $text;
}

sub _postformat {
    my $self      = shift;
    my $text      = shift;
    my $raa_rules = shift;
    my $text_orig = $text; # keep a copy

    # remove duplicates
    my @before_pieces = split(/,/, $text);
    my %seen;
    my @after_pieces;
    foreach my $piece (@before_pieces){
        $piece =~s/^\s+//g;
        $seen{$piece}++;
        next if ($seen{$piece} > 1);
        push(@after_pieces,$piece);
    }
    $text = join(', ', @after_pieces);

    # do any country specific rules
    foreach my $ra_fromto ( @$raa_rules ){
        try {
            my $regexp = qr/$ra_fromto->[0]/;	    
	    #say STDERR 'text: ' . $text;
	    #say STDERR 're: ' . $regexp;
            my $replacement = $ra_fromto->[1];

            # ultra hack to do substitution
            # limited to $1 and $2, should really be a while loop
            # doing every substitution

            if ($replacement =~ m/\$\d/){
                if ($text =~ m/$regexp/){
                    my $tmp1 = $1;
                    my $tmp2 = $2;
		    $replacement =~ s/\$1/$tmp1/;
		    $replacement =~ s/\$2/$tmp2/;
                }
            }
	    $text =~ s/$regexp/$replacement/;
        }
        catch {
            warn "invalid replacement: " . join(', ', @$ra_fromto)
        };
    }
    return $text;
}

sub _sanity_cleaning {
    my $self = shift;
    my $rh_components = shift || return; 
    if (defined($rh_components->{'postcode'})
        && (length($rh_components->{'postcode'}) > 20)
    ){
        delete $rh_components->{'postcode'};
    }

    # catch values containing URLs
    foreach my $c (keys %$rh_components){
        if ($rh_components->{$c} =~ m|https?://|){
            delete $rh_components->{$c};
        }
    }
    return;
}


sub _minimal_components {
    my $self = shift;
    my $rh_components = shift || return;
    my @required_components = qw(road postcode); #FIXME - should be in conf
    my $missing = 0;  # number of required components missing
  
    my $minimal_threshold = 2;
    foreach my $c (@required_components){
        $missing++ if (!defined($rh_components->{$c}));
        return 0 if ($missing == $minimal_threshold);
    }
    return 1;
}

my %valid_replacement_components = (
    'state' => 1,
);

# determines which country code to use
# may also override other configuration if we are dealing with 
# a dependent territory
sub _determine_country_code {
    my $self          = shift;
    my $rh_components = shift || return;

    # FIXME - validate it is a valid country
    return if (!defined($rh_components->{country_code}));

    if ( my $cc = lc($rh_components->{country_code}) ){

        # is it two letters long?
        return if ( $cc !~ m/^[a-z][a-z]$/);
        return 'GB' if ($cc eq 'uk');

        $cc = uc($cc); 

        # check if the configuration tells us to use 
        # the configuration of another country
        # used in cases of dependent territories like
        # American Samoa (AS) and Puerto Rico (PR)
        if ( defined( $self->{templates}{$cc} )
             && defined( $self->{templates}{$cc}{use_country} )
        ){
            my $old_cc = $cc;
            $cc = $self->{templates}{$cc}{use_country};
            if (defined( $self->{templates}{$old_cc}{change_country} )){
		$rh_components->{country} = 
		    $self->{templates}{$old_cc}{change_country};
            } 
            if (defined( $self->{templates}{$old_cc}{add_component} )){
                my $tmp = $self->{templates}{$old_cc}{add_component};
                my ($k,$v) = split(/=/,$tmp);
                # check whitelist of valid replacement components
                if (defined( $valid_replacement_components{$k} )){
		    $rh_components->{$k} = $v;
		}
            } 
        }

#        warn "cc $cc";
#        warn Dumper $rh_components;

        if ($cc eq 'NL'){
            if (defined($rh_components->{state})){
		if ($rh_components->{state} eq 'Curaçao'){
		    $cc = 'CW';
		    $rh_components->{country} = 'Curaçao';
		}
		elsif ($rh_components->{state} =~ m/^sint maarten/i){
		    $cc = 'SX';
		    $rh_components->{country} = 'Sint Maarten';
		}
		elsif ($rh_components->{state} =~ m/^Aruba/i){
		    $cc = 'AW';
		    $rh_components->{country} = 'Aruba';
		}
	    }
	}
        return $cc;
    }
    return;
}

# sets and returns a state code
sub _fix_country {
    my $self          = shift;
    my $rh_components = shift || return;

    #warn Dumper $rh_components;
    # is the country a number?
    # if so, and there is a state, use state as country
    if (defined($rh_components->{country})){
	if (defined($rh_components->{state}) ){
            if (looks_like_number($rh_components->{country})){
		$rh_components->{country} = $rh_components->{state};
                delete $rh_components->{state}
	    }
        }
    }

    return;
}

# sets and returns a state code
sub _add_state_code {
    my $self          = shift;
    my $rh_components = shift;

    return if $rh_components->{state_code};
    return if !$rh_components->{state};
    return if !$rh_components->{country_code};
    # ensure it is uppercase
    $rh_components->{country_code} = uc($rh_components->{country_code});

    if ( my $mapping = $self->{state_codes}{$rh_components->{country_code}} ){
        foreach ( keys %$mapping ){
            if ( uc($rh_components->{state}) eq uc($mapping->{$_}) ){
                $rh_components->{state_code} = $_;
            }
        }
    }
    return $rh_components->{state_code};
}

sub _apply_replacements {
    my $self          = shift;
    my $rh_components = shift;
    my $raa_rules     = shift;

    #warn "in _apply_replacements";
    #warn "  raa_rules";
    #warn Dumper $raa_rules;
    #warn "  rh_components";
    #warn Dumper $rh_components;

    foreach my $component ( sort keys %$rh_components ){
        foreach my $ra_fromto ( @$raa_rules ){
            try {
                # do key specific replacement
                if ($ra_fromto->[0] =~ m/^$component=/){
                    my $from = $ra_fromto->[0]; 
                    $from =~ s/^$component=//;
                    if ($rh_components->{$component} eq $from){
			$rh_components->{$component} = $ra_fromto->[1]; 
   		    }
		} else {

		    my $regexp = qr/$ra_fromto->[0]/;
		    $rh_components->{$component} =~ s/$regexp/$ra_fromto->[1]/;
		}
            }
            catch {
                warn "invalid replacement: " . join(', ', @$ra_fromto)
            };
        }
    }
    return $rh_components;
}

# " abc,,def , ghi " => 'abc, def, ghi'
sub _clean {
    my $self = shift;
    my $out  = shift // '';
    $out =~ s/[\},\s]+$//;
    $out =~ s/^[,\s]+//;

    $out =~ s/,\s*,/, /g; # multiple commas to one   
    $out =~ s/\s+,\s+/, /g; # one space behind comma

    $out =~ s/\s\s+/ /g; # multiple whitespace to one
    $out =~ s/,,+/,/g; # multiple commas to one

    $out =~ s/^\s+//;
    $out =~ s/\s+$//;
    return $out;
}

sub _render_template {
    my $self       = shift;
    my $THTemplate = shift;
    my $components = shift;

    # Mustache calls it context
    my $context = clone($components);
    $context->{first} = sub {
        my $text = shift;
        my $newtext = $THC->compile($text, {'numeric_string_as_string' => 1})->render($components);
        my $selected = first { length($_) } split(/\s*\|\|\s*/, $newtext);
        return $selected;
    };
    
    my $output = $THTemplate->render($context);
    $output = $self->_clean($output);

    # is it empty?
    if ($output !~ m/\w/){
        my @comps = sort keys %$components;
        if (scalar(@comps) == 1){  
            foreach my $k (@comps){
                $output = $components->{$k};
            }
        } # FIXME what if more than one?
    }
    return $output;
}

# note: unsorted list because $cs is a hash!
# returns []
sub _find_unknown_components { 
    my $self       = shift;
    my $components = shift;

    my %h_known = map { $_ => 1 } @{ $self->{ordered_components} };
    my @a_unknown = grep { !exists($h_known{$_}) } sort keys %$components;

    #warn Dumper \@a_unknown;
    return \@a_unknown;
}

1;
