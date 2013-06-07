# Copyright (C) 2013 Igor Afanasyev, https://github.com/iafan/Config-Neat

=head1 NAME

Config::Neat::Schema - Validate Config::Neat files against schema

=head1 SYNOPSIS

File 01.nconf:

    foo {
        bar         baz etc

        etc {
            pwd     1 2
        }
    }
    abc             def

File schema.nconf:

    foo
    {
        bar         ARRAY
        etc
        {
            *       ARRAY
            pwd     STRING
        }
    }
    data            DATA
    
if file 01.nconf is validated against schema.nconf, it will:
1) convert arrays to strings for the known nodes with 'STRING' type
2) die or warn (depending on the settings) when an unknown node is found
   (in the example above, 'abc').

'*' as the name of the node means 'node with any name'. If such catch-all rule
is not specified, all possible node values need to be specified explicitly.

Possible type specifiers are: HASH (this is default if not specified),
ARRAY, STRING, ARRAY_OR_HASH, STRING_OR_HASH, or DATA. 'DATA' nodes may contain
any arbitrary data structure and are not validated.

=cut

package Config::Neat::Schema;

our $VERSION = '0.1';

use strict;

use Config::Neat;
use File::Spec::Functions qw(rel2abs);
use File::Basename qw(dirname);
use Tie::IxHash;

#
# Initialize object
#
sub new {
    my ($class) = @_;

    my $self = {};

    bless $self, $class;
    return $self;
}

# Given file name, will read and store the schema file
sub load {
    my ($self, $filename, $binmode) = @_;
    my $c = Config::Neat->new();
    return $self->{schema} = $c->parse_file($filename, $binmode);
}

# Validates provided data structure (parsed config file) against the previously loaded schema
# with expanded '@inherit' blocks
sub validate {
    my ($self, $data) = @_;
    die "Schema should be loaded prior to validation" unless defined $self->{schema};
    return $self->validate_node($self->{schema}, $data, undef, undef, []);
}

sub validate_node {
    my ($self, $schema_node, $data_node, $parent_data, $parent_data_key, $path) = @_;

    my $pathstr = '/'.join('/', @$path);

    if (!$schema_node) {
        die "Node '$pathstr' is not defined in the schema";
    }

    my $schema_type = $self->get_node_type($schema_node);
    my $data_type = $self->get_node_type($data_node);

    if ($schema_type eq 'ARRAY') {
        # the string representation of the node contains the type definition
        $schema_type = $schema_node->as_string;
    } elsif ($schema_type eq 'HASH' and defined $schema_node->{''}) {
        # if it's a hash, the the string representation of the node's default parameter
        # may contain the type definition override
        $schema_type = $schema_node->{''}->as_string if exists $schema_node->{''};
    }

    # disambiguate fuzzy node schema types
    if ($schema_type eq 'ARRAY_OR_HASH') {
        $schema_type = ($data_type eq 'HASH') ? 'HASH' : 'ARRAY';
    }

    if ($schema_type eq 'STRING_OR_HASH') {
        $schema_type = ($data_type eq 'HASH') ? 'HASH' : 'STRING';
    }

    # data nodes of type ARRAY are converted to STRING automatically
    if ($schema_type eq 'STRING' and $data_type eq 'ARRAY') {
        $parent_data->{$parent_data_key} = $data_node = $data_node->as_string;
        $data_type = $self->get_node_type($data_node);
    }

    if ($schema_type ne $data_type) {
        die "'$pathstr' is $data_type, while it is expected to be $schema_type";
    }

    if ($data_type eq 'HASH') {
        foreach my $key (keys %$data_node) {
            if ($key eq '') {
                # TODO: check if the default parameter for the hash is allowed, and if it is a string or array
            } else {
                my $schema_subnode = $schema_node->{$key} || $schema_node->{'*'};
                my @a = @$path;
                push @a, $key;
                $self->validate_node($schema_subnode, $data_node->{$key}, $data_node, $key, \@a);
            }
        }
        return 1;
    }

    return 1;
}

sub get_node_type {
    my ($self, $node) = @_;
    return 'HASH' if ref($node) eq 'HASH';
    return 'ARRAY' if ref($node) eq 'Config::Neat::Array' or ref($node) eq 'ARRAY';
    return 'STRING' if ref(\$node) eq 'SCALAR';
    return 'UNKNOWN';
}