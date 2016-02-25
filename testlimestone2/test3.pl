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


$con->write_query(Carbon::Limestone::Query->new(
	type => 'create',
	target => 'Limestone::Table=test_table',
	data => {
		columns => {
			valu32 => 'UINT32',
			valu16 => 'UINT16',
			valu8 => 'UINT8',
			vali32 => 'INT32',
			vali16 => 'INT16',
			vali8 => 'INT8',
			valc8 => 'CHAR_8',
			vals8 => 'STRING_8',
		}
	},
));
say Dumper $con->read_result_blocking;



$con->write_query(Carbon::Limestone::Query->new(type => 'list', target => 'Limestone::Table=test_table'));
say Dumper $con->read_result_blocking;

say "sending three inserts:";
$con->write_query(Carbon::Limestone::Query->new(
	type => 'query', 
	target => 'Limestone::Table=test_table',
	data => {
		type => 'insert',
		entries => [
			{
				valu32 => 0xffffffff,
				valu16 => 0xffff,
				valu8 => 0xff,
				vali32 => -1000000,
				vali16 => -1000,
				vali8 => -15,
				valc8 => "asdfasdf",
				vals8 => 'user',
			},
			{
				vali32 => -1000000,
				vali16 => -1000,
				vali8 => -15,
				valc8 => "qwerty",
				vals8 => 'password',
			},
			# {
			# 	key => 5,
			# 	val => 6,
			# },
			# {
			# 	key => 1337,
			# 	val => 0x1337,
			# },
			# {
			# 	key => 1000,
			# 	val => 100,
			# }
		]
	},
));
say Dumper $con->read_result_blocking;





