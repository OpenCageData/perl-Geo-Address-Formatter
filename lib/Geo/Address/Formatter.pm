# ABSTRACT: take structured address data and format it according to the various global/country rules

package Geo::Address::Formatter;

use strict;
use warnings;

use Clone qw(clone);
use Data::Dumper;
use File::Basename qw(dirname);
use File::Find::Rule;
use List::Util qw(first);
use Mustache::Simple;
use Try::Tiny;
use YAML qw(Load LoadFile);

my $tache = Mustache::Simple->new;

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

    try {
        my @c = LoadFile($path . '/components.yaml');

        foreach my $rh_c (@c){
            if (defined($rh_c->{aliases})){
                foreach my $alias (@{$rh_c->{aliases}}){
                    $self->{component_aliases}{$alias} = $rh_c->{name};
                }
            }
        }
        #warn Dumper $self->{component_aliases};
        #warn Dumper \@c;
        $self->{ordered_components} = 
            [ map { $_->{name} => ($_->{aliases} ? @{$_->{aliases}} : ()) } @c];
    }
    catch {
        warn "error parsing component configuration: $_";
    };

    $self->{state_codes} = {};
    if ( -e $path . '/state_codes.yaml'){
        try {
            my $rh_c = LoadFile($path . '/state_codes.yaml');
            # warn Dumper $rh_c;
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

    # set the aliases
    foreach my $alias (keys %{$self->{component_aliases}}){
        if (defined($rh_components->{$alias})){     
            $rh_components->{$self->{component_aliases}->{$alias}} = 
                $rh_components->{$alias};
        }
    }

    # determine the template
    my $rh_config = $self->{templates}{uc($cc)} || $self->{templates}{default};
    my $template_text = $rh_config->{address_template};

    #print STDERR "t text " . Dumper $template_text;
    #print STDERR "comp " . Dumper $rh_components;

    # do we have the minimal components for an address?
    # or should we instead use the fallback template?
    if (!$self->_minimal_components($rh_components)){
        $template_text = 
            $rh_config->{fallback_template}
            || $self->{templates}{default}{fallback_template}
            || $rh_config->{address_template};  # if there is no fallback
    }

    # clean up the components
    $self->_apply_replacements($rh_components, $rh_config->{replace});
    $self->_add_state_code($rh_components);

    # add the attention
    $rh_components->{attention} = join(', ', map { $rh_components->{$_} } @{ $self->_find_unknown_components($rh_components)} );
    #warn Dumper $rh_components;
    # render it
    my $text = $self->_render_template($template_text, $rh_components);
    $text = $self->_postformat($text,$rh_config->{postformat_replace});
    $text = $self->_clean($text);
    return $text;
}

sub _postformat {
    my $self        = shift;
    my $text  = shift;
    my $raa_rules   = shift;

    foreach my $ra_fromto ( @$raa_rules ){
        try {
            my $regexp = qr/$ra_fromto->[0]/;
            $text =~ s/$regexp/$ra_fromto->[1]/;
        }
        catch {
            warn "invalid replacement: " . join(', ', @$ra_fromto)
        };
    }
    return $text;
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

sub _determine_country_code {
    my $self       = shift;
    my $components = shift || return;

    # FIXME - validate it is a valid country
    if (my $cc = $components->{country_code} ){
        return if ( $cc !~ m/^[a-z][a-z]$/i);
        return 'GB' if ($cc =~ /uk/i);
        return uc($cc);
    }
    return;
}

# sets and returns a state code
sub _add_state_code {
    my $self       = shift;
    my $components = shift;

    ## TODO: what if the cc was given as an option?
    my $cc = $self->_determine_country_code($components) || '';

    return if $components->{state_code};
    return if !$components->{state};

    if ( my $mapping = $self->{state_codes}{$cc} ){
        foreach ( keys %$mapping ){
            if ( uc($components->{state}) eq uc($mapping->{$_}) ){
                $components->{state_code} = $_;
            }
        }
    }
    return $components->{state_code};
}

sub _apply_replacements {
    my $self        = shift;
    my $components  = shift;
    my $raa_rules   = shift;

    foreach my $key ( keys %$components ){
        foreach my $ra_fromto ( @$raa_rules ){

            try {
                my $regexp = qr/$ra_fromto->[0]/;
                $components->{$key} =~ s/$regexp/$ra_fromto->[1]/;
            }
            catch {
                warn "invalid replacement: " . join(', ', @$ra_fromto)
            };
        }
    }
    return $components;
}

# " abc,,def , ghi " => 'abc, def, ghi'
sub _clean {
    my $self = shift;
    my $out  = shift // '';
    $out =~ s/[,\s]+$//;
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
    my $self             = shift;
    my $template_content = shift;
    my $components       = shift;

    # Mustache calls it context
    my $context = clone($components);

    $context->{first} = sub {
        my $text = shift;
        $text = $tache->render($text, $components);
        my $selected = first { length($_) } split(/\s*\|\|\s*/, $text);
        return $selected;
    };
    $template_content =~ s/\n/, /sg;
    my $output = $tache->render($template_content, $context);
    
    $output = $self->_clean($output);
    return $output;
}

# note: unsorted list because $cs is a hash!
# returns []
sub _find_unknown_components {
    my $self       = shift;
    my $components = shift;

    my %h_known = map { $_ => 1 } @{ $self->{ordered_components} };
    my @a_unknown = grep { !exists($h_known{$_}) } keys %$components;

    #warn Dumper \@a_unknown;
    return \@a_unknown;
}

1;
