package TeXDown::Scrivener::TBinder;

=pod

=head1 NAME

TeXDown::Scrivener::TBinder Hold the Binder of a Scrivx file.

=head1 DESCRIPTION

This class holds the Binder of a Scrivx file.

You can use it like so:

    # Initialize, or rather, reuse from elsewhere...

    my $parser = TeXDown::Scrivener::TBinder->new;

=head1 METHODS

=cut



use warnings;
use strict;

#use version; our $VERSION = qv('0.0.3');

binmode STDOUT, ":utf8";
use utf8;
use Carp qw(carp cluck croak confess);
use feature qw(say);
use Data::Dump "pp";
use Pod::Usage;
use File::Basename;
use Cwd qw(abs_path);

use XML::LibXML;

use Moose;
with 'MooseX::Log::Log4perl';

use namespace::autoclean -except => sub { $_ =~ m{^t_.*} };

use TeXDown::TConfig;
use TeXDown::TUtils qw/ t_as_string t_split /;
use TeXDown::Scrivener::TBinderItem;

=begin testing SETUP

###################################################
#
# Test Setup
#
###################################################

my $MODULE       = 'TeXDown::Scrivner::TBinder';

my @DEPENDENCIES = qw / TeXDown::Scrivener::TBinderItem
                        TeXDown::TConfig
                        TeXDown::TUtils
                      /;

my $INI          = 't/texdown-test.ini';

# Mostly dynamic construction of module path
###################################################

use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname( abs_path $0) . '/../lib';

binmode STDOUT, ":utf8";
use utf8;
use feature qw(say);
use Data::Dump "pp";
use Module::Load;

###################################################
#
# Set up logging
#

use Log::Log4perl qw(get_logger :levels);
Log::Log4perl->init( dirname( abs_path $0) . "/../log4p.ini" );


# Load Dependencies and set up loglevels

foreach my $dependency (@DEPENDENCIES) {
    load $dependency;
    if ( exists $ENV{LOGLEVEL} && "" ne $ENV{LOGLEVEL} ) {
        get_logger($dependency)->level( uc $ENV{LOGLEVEL} );
    }
}

my $log = get_logger($MODULE);

# For some reason, some test
# runs have linefeed issues
# for their first statement

print STDERR "\n";

#
###################################################

###################################################
#
# Initial shared code for all tests of this module
#
###################################################

our $cfg      = TeXDown::TConfig->new;

$cfg->load($INI);

=end testing

=cut

has binderitems => (
    traits  => ['Array'],
    is      => 'rw',
    isa     => 'ArrayRef[TeXDown::Scrivener::TBinderItem]',
    default => sub { [] },
    lazy    => 0,
);

has binderitems_by_title => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef[ArrayRef[TeXDown::Scrivener::TBinderItem]]',
    default => sub { {} },
    lazy    => 0,
);


has binderitems_by_id => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef[TeXDown::Scrivener::TBinderItem]',
    default => sub { {} },
    lazy    => 0,
);



=begin testing Construct

    ok( 1 == 1, 'Passed: Construct' );

=end testing

=cut

sub BUILD {
    my ( $self, $arg_ref ) = @_;
    $self->log->trace("Instantiated TBinder");
}

sub load {
    my ( $self, $el ) = @_;

    $self->log->trace("Loading TBinder");

    my @xml_binderitems = $el->findnodes('BinderItem');

    foreach my $xml_binderitem (@xml_binderitems) {
        my $binderitem = TeXDown::Scrivener::TBinderItem->new(
            binder => $self
        );
        $binderitem->load($xml_binderitem);
        $self->add($binderitem);
    }

    $self->log->trace(
        "Loaded " . $self->size . " binder items for this binder" );
}

sub add {
    my ( $self, $binderitem ) = @_;

    push( @{ $self->binderitems }, $binderitem );

    $self->track($binderitem);
}


#
# Add the shortcuts for each binder item
#
sub track {
    my ( $self, $binderitem ) = @_;

    #
    # Track by Titles
    #
    my %htitles = %{ $self->binderitems_by_title };

    my @arr;

    if ( exists $htitles{ $binderitem->title } ) {
        @arr = @{ $htitles{ $binderitem->title } };
        push( @arr, $binderitem );
    }
    else {
        @arr = ($binderitem);
        $htitles{ $binderitem->title } = \@arr;
        $self->binderitems_by_title( \%htitles );
    }

    #
    # Track by IDs (simpler, since we assume IDs are unique)
    #
    my %hids = %{ $self->binderitems_by_id };
    $hids{ $binderitem->id } = $binderitem;
    $self->binderitems_by_id( \%hids );
}

#
# When we parse our binder, we create a new binder which will
# contain the flat list of binderitems that we will then next
# output.
#
sub parse {
    my ($self) = @_;

    $self->log->trace("> Parse process");

    my $binderitems = $self->binderitems;

    my $result = TeXDown::Scrivener::TBinder->new;

    my @projects = @{ $::cfg->get( 'p', { 'as_array' => 1 } ) };

    foreach my $project (@projects) {
        if ( $project =~ "^/.*" ) {
            #
            # Absolute location
            #
            #$self->log->trace( "+ Parsing p = " . $project );

            ## Split the path into an array
            #my @locations = t_split( "/", $project );

            #my $binderitem = $self->get_child( { title => @locations[0] } );

            #if (defined $binderitem) {

            #}

        }
        elsif ( $project =~ /^-?\d+$/ ) {
            #
            # Giving directly a project Id
            #
            #foreach my $binderItem (
            #    $doc->findnodes( '//BinderItem[@ID="' . $project . '"]' ) )
            #{
            #    printNode( $binderItem, "", 0, $dir );
            #}
        }
        else {
            #
            # Relative location; /Children/* are being resolved by recursion
            #
            my $binderitems = $self->by_title($project);

            foreach my $binderitem (@$binderitems) {
                $binderitem->print(
                    {   parent => $binderitem,
                        path   => "",
                        level  => 0,
                    }

                );
            }

        }
    }


    $self->log->trace("< Parse process");
}

sub by_title {
    my ( $self, $title ) = @_;

    my %htitles = %{ $self->binderitems_by_title };

    my @arr;

    if ( exists $htitles{$title} ) {
        @arr = @{ $htitles{$title} };
    }

    return \@arr;
}


sub size {
    my ($self) = @_;

    return scalar @{ $self->binderitems };
}


sub describe {
    my ($self) = @_;

    return $self->binderitems;
}

sub dump {
    my ($self) = @_;
    $Data::Dumper::Terse = 1;
    $self->log->trace( sub { Data::Dumper::Dumper( $self->describe() ) } );
}



no Moose;
__PACKAGE__->meta->make_immutable;

1;
