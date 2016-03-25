#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Data::Dumper;

use lib '..';
use Carbon::Limestone::Connection;
use Carbon::Limestone::Query;




my $con = Carbon::Limestone::Connection->new;


my $error = $con->connect_client('localhost:2049', root => 'root');
die $error if defined $error;


my $client = $con->client('Limestone::Table=test_table');



my $insert_id = $client->insert(
	{ key => 200, index => 6, val => 'strawberry', },
	{ key => 400, index => 7, val => 'pinapple', },
	{ key => 300, index => 8, val => 'bear', },
	{ key => 1000, index => 9, val => 'pomogranate', },
	{ key => 14, index => 10, val => 'jelly', },
	{ key => 0, index => 11, val => 'mystery', },
);


my $delete_id = $client->delete( where => { val => 'eq "mystery"' } );


my $get_id = $client->get( where => { index => '<= 6' } );



say Dumper $client->result;
say Dumper $client->result($insert_id);
say Dumper $client->result($delete_id);



