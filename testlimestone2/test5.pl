#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Data::Dumper;

use lib '..';
use Carbon::Limestone::Connection;
use Carbon::Limestone::Query;




my $con = Carbon::Limestone::Connection->new;


my $error = $con->connect_client('localhost:2049');
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


# $con->write_query(Carbon::Limestone::Query->new(
# 	type => 'create',
# 	target => 'Limestone::Table=test_table',
# 	data => {
# 		columns => {
# 			index => 'UINT32',
# 			key => 'INT32',
# 			val => 'STRING_12',
# 		}
# 	},
# ));
# # say Dumper $con->read_result_blocking;





# my $list_id = $con->write_query(Carbon::Limestone::Query->new(type => 'list', target => 'Limestone::Table=test_table'));
# # say Dumper $con->read_result_blocking;

# my $insert_id = $con->write_query(Carbon::Limestone::Query->new(
# 	type => 'query',
# 	target => 'Limestone::Table=test_table',
# 	data => {
# 		type => 'insert',
# 		entries => [
# 			{
# 				index => 1,
# 				key => 5,
# 				val => 'apple',
# 			},
# 			{
# 				index => 2,
# 				key => 1337,
# 				val => '31373',
# 			},
# 			{
# 				index => 3,
# 				key => 1000,
# 				val => 'not here',
# 			},
# 			{
# 				index => 4,
# 				key => -5,
# 				val => 'orange',
# 			},
# 			{
# 				index => 5,
# 				key => -1000,
# 				val => 'pear',
# 			},
# 		]
# 	},
# ));
# # say Dumper $con->read_result_blocking;

# say "my ids: $list_id, $insert_id";

# say Dumper $con->read_result_id_blocking($insert_id);
# say Dumper $con->read_result_id_blocking($list_id);
# # say Dumper $con->id_cache;


