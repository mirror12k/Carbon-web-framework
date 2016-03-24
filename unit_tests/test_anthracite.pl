#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use LWP::UserAgent;
use WWW::Mechanize;
use threads;
use Carp;

use lib '..';
use Carbon::Nanotube;
use Carbon::Request;
use Carbon::URI;



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


sub test_basic {
	my $success = 1;
	my ($res, $req);
	my $test_name = 'test basic';

	my $rtr = Carbon::Nanotube->new;
	$rtr->init_thread;

	$res = $rtr->execute_dynamic_file('test_anthracite_test_basic/hello_world.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	# say "got result: ", $res->as_string;
	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', 'hello world!']);

	$res = $rtr->execute_dynamic_file('test_anthracite_test_basic/query_form.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', "query:\n"]);

	$res = $rtr->execute_dynamic_file('test_anthracite_test_basic/query_form.am', Carbon::Request->new('GET', Carbon::URI->parse('/?b=a&a=c')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', "query:\na=>c\nb=>a\n"]);

	$res = $rtr->execute_dynamic_file('test_anthracite_test_basic/query_form.am', Carbon::Request->new('GET', Carbon::URI->parse('/?hello=world&test=asdf')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', "query:\nhello=>world\ntest=>asdf\n"]);

	$res = $rtr->execute_dynamic_file('test_anthracite_test_basic/post_form.am',
		Carbon::Request->new('GET', Carbon::URI->parse('/'), { 'content-type' => ['application/x-www-form-urlencoded'] }, 'hello=world&test=asdf'));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', "post:\nhello=>world\ntest=>asdf\n"]);

	$res = $rtr->execute_dynamic_file('test_anthracite_test_basic/post_form.am',
		Carbon::Request->new('GET', Carbon::URI->parse('/'), { 'content-type' => ['application/x-www-form-urlencoded'] }, ''));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', "post:\n"]);

	$res = $rtr->execute_dynamic_file('test_anthracite_test_basic/redirect.am',
		Carbon::Request->new('GET', Carbon::URI->parse('/'), { 'content-type' => ['application/x-www-form-urlencoded'] }, ''));

	$success = $success and test_results($test_name =>
		[$res->code, $res->header('location')],
		['303', "/lolredirect"]);


	warn "$test_name passed\n" if $success;
	return $success
}


sub test_include {
	my $success = 1;
	my ($res, $req);
	my $test_name = 'test include';

	my $rtr = Carbon::Nanotube->new;
	$rtr->init_thread;

	$res = $rtr->execute_dynamic_file('test_anthracite_test_basic/include_test.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', 'hello world!']);
	$res = $rtr->execute_dynamic_file('test_anthracite_test_basic/subdir/long_include.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	# say "got result: ", $res->as_string;
	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', 'hello world!']);


	warn "$test_name passed\n" if $success;
	return $success
}

warn "anthracite testing:\n";

test_basic;
test_include;

warn "done\n";
