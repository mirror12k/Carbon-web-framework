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

# $con->write_query(Carbon::Limestone::Query->new(type => 'init', collection => $name));

# say Dumper $con->read_result_blocking;




$con->write_query(Carbon::Limestone::Query->new(type => 'list', target => '*'));
say Dumper $con->read_result_blocking;


$con->write_query(Carbon::Limestone::Query->new(type => 'create', target => 'Limestone::Table=test_table'));
say Dumper $con->read_result_blocking;


$con->write_query(Carbon::Limestone::Query->new(type => 'list', target => '*'));
say Dumper $con->read_result_blocking;


$con->write_query(Carbon::Limestone::Query->new(type => 'create', target => 'Limestone::Table=test_table2'));
say Dumper $con->read_result_blocking;

$con->write_query(Carbon::Limestone::Query->new(type => 'query', target => 'Limestone::Table=test_table'));
say Dumper $con->read_result_blocking;

$con->write_query(Carbon::Limestone::Query->new(type => 'query', target => 'Limestone::Table=test_table3'));
say Dumper $con->read_result_blocking;

$con->write_query(Carbon::Limestone::Query->new(type => 'list', target => 'Limestone::Table=test*'));
say Dumper $con->read_result_blocking;

$con->write_query(Carbon::Limestone::Query->new(type => 'delete', target => 'Limestone::Table=test_table'));
say Dumper $con->read_result_blocking;

$con->write_query(Carbon::Limestone::Query->new(type => 'list', target => '*'));
say Dumper $con->read_result_blocking;




# # sleep 5;

# # for my $i (1 .. 1000) {
# # 	$con->write_query(Carbon::Limestone::Query->new(type => 'append', collection => $name, data => [
# # 		{ doc => 'hello world!', count => 16, message => ('hello world' x 100) },
# # 		{ doc => "i am $name!", count => -1, message => ('i am name' x 100) },
# # 		{ doc => "john doe", count => 5, message => ('doe john' x 100) },
# # 		{ doc => "jane doe", count => 3, message => ('jane jane' x 100) },
# # 		{ doc => "cookie dough", count => 14, message => ('makes cookies' x 100) },
# # 		{ doc => "parrot", count => 6, message => ('cracker' x 100) },
# # 	]));
# # 	# say Dumper $con->read_result;
# # 	$con->read_result;
# # 	say "written $i";
# # }

# $con->write_query(Carbon::Limestone::Query->new(type => 'append', collection => $name, data => [
# 	{ doc => 'hello world!', count => 16, message => 'hello world' },
# 	{ doc => "i am $name!", count => -1, message => 'i am name' },
# 	{ doc => "john doe", count => 5, message => 'doe john' },
# 	{ doc => "jane doe", count => 3, message => 'jane jane' },
# 	{ doc => "cookie dough", count => 14, message => 'makes cookies' },
# 	{ doc => "parrot", count => 6, message => 'cracker' },
# ]));
# say Dumper $con->read_result;


# # $con->write_query(Carbon::Limestone::Query->new(type => 'query', collection => $name));
# # $con->write_query(Carbon::Limestone::Query->new(type => 'query', collection => $name, data => { limit => { count => 8 }}));
# $con->write_query(Carbon::Limestone::Query->new(type => 'query', collection => $name, data => { where => { count => '== 6' }, limit => { count => 100 } }));
# say Dumper $con->read_result;





