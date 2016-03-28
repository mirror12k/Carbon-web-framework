#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use threads;
use Carp;
use File::Path;

use lib '..';
use Carbon::Limestone;
use Carbon::Limestone::Client;



sub test_results {
	my ($test_name, $test_values, $expected_values) = @_;

	my $success = 1;
	for my $i (0 .. $#$test_values) {
		if ($test_values->[$i] ne $expected_values->[$i]) {
			confess "$test_name failed: server returned: [$test_values->[$i]], expected: [$expected_values->[$i]]";
			$success = 0;
		}
	}

	return $success
}



sub test_table {
	my $success = 1;
	my ($res, $req);
	my $test_name = 'test table';

	# clear the test directory in case it's left over from the last time
	rmtree('test_limestone_test_table');

	my $thr = threads->create(sub {
		my $svr = Carbon::Limestone->new(
			ssl_certificate => 'test_ssl_test_basic/cert.pem', # cheat by using the test_ssl certificate
			ssl_key => 'test_ssl_test_basic/key.pem',
			port => 2049,
			database_filepath => 'test_limestone_test_table' );

		$SIG{INT} = sub { $svr->shutdown; };

		$svr->start_server;
	});

	sleep 1;

	my $client = Carbon::Limestone::Client->new(hostport => 'localhost:2049', username => 'root', password => 'root');

	$res = $client->create('Limestone::Table=test_table' => { columns => { key => 'STRING_16', val => 'UINT32', index => 'INT8' } });
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success],
		[1]);


	$res = $client->list('*');
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success, scalar(@{$res->data}), $res->data->[0]],
		[1, 1, 'Limestone::Table=test_table']);


	my $table = $client->client('Limestone::Table=test_table');

	$res = $table->insert({ key => 'asdf', val => 15, index => 1 }, { key => 'qwerty', val => 30, index => 2 }, { key => 'new', val => 1337, index => 3 });
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success, $res->data],
		[1, 3]);

	$res = $table->get(where => { index => '== 2' });
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success, scalar(@{$res->data}), $res->data->[0]->{key}, $res->data->[0]->{val}, $res->data->[0]->{index}],
		[1, 1, 'qwerty', 30, 2]);

	$res = $table->get(where => { key => 'ne "qwerty"' });
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success, scalar(@{$res->data}),
			$res->data->[0]->{key}, $res->data->[0]->{val}, $res->data->[0]->{index},
			$res->data->[1]->{key}, $res->data->[1]->{val}, $res->data->[1]->{index}],
		[1, 2, 'asdf', 15, 1, 'new', 1337, 3]);

	$res = $table->get;
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success, scalar(@{$res->data})],
		[1, 3]);

	$res = $table->delete;
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success, $res->data],
		[1, 3]);

	$res = $table->get;
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success, scalar(@{$res->data})],
		[1, 0]);


	$res = $client->delete('Limestone::Table=test_table');
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success],
		[1]);

	$res = $client->list('*');
	warn "error: ", $res->error if $res->is_error;

	$success = $success and test_results($test_name =>
		[$res->is_success, scalar(@{$res->data})],
		[1, 0]);



	warn "$test_name passed\n" if $success;

	$thr->kill('SIGINT');
	$thr->join;

	rmtree('test_limestone_test_table');

	return $success
}




warn "limestone testing:\n";

test_table;

warn "done\n";

