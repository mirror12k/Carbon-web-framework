#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';


use lib '..';
use Carbon::Limestone::Connection;
use Carbon::Limestone::Query;
use Data::Dumper;




my $con = Carbon::Limestone::Connection->new;


my $error = $con->connect_client('localhost:2049');
die $error if defined $error;

my $name = shift // "new_collection";

$con->write_query(Carbon::Limestone::Query->new(type => 'init', collection => $name));

say Dumper $con->read_result_blocking;









