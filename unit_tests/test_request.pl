#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Carp;

use lib '..';
use Carbon::Request;




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



sub test_request_compiling {
	my $success = 1;
	my ($req);
	my $test_name = 'test request compiling';

	$req = Carbon::Request->new;
	$success = $success and test_results($test_name => [$req->as_string], ["GET / HTTP/1.1\r\n\r\n"]);

	$req->method('POST');
	$req->uri('/asdf?qwert');
	$success = $success and test_results($test_name => [$req->as_string], ["POST /asdf?qwert HTTP/1.1\r\n\r\n"]);

	$req->header(Host => 'asdf.com');
	$success = $success and test_results($test_name => [$req->as_string], ["POST /asdf?qwert HTTP/1.1\r\nhost: asdf.com\r\n\r\n"]);

	$req->remove_header('host');
	$req->header(Cookie => [qw/ hello world /]);
	$success = $success and test_results($test_name => [$req->as_string], ["POST /asdf?qwert HTTP/1.1\r\ncookie: hello\r\ncookie: world\r\n\r\n"]);

	$req->content('testing');
	$success = $success and test_results($test_name => [$req->as_string], ["POST /asdf?qwert HTTP/1.1\r\ncookie: hello\r\ncookie: world\r\n\r\ntesting"]);


	warn "$test_name passed\n" if $success;

	return $success
}


sub test_request_parsing {
	my $success = 1;
	my ($req);
	my $test_name = 'test request parsing';


	$req = Carbon::Request->parse("GET / HTTP/1.1\r\n\r\n");
	$success = $success and test_results($test_name => [$req->method, $req->uri, $req->protocol, $req->content],
		["GET", '/', 'HTTP/1.1', '']);


	$req = Carbon::Request->parse("POST /asdf?qwert HTTP/1.1\r\n\r\n");
	$success = $success and test_results($test_name => [$req->method, $req->uri, $req->protocol, $req->content],
		["POST", '/asdf?qwert', 'HTTP/1.1', '']);

	$req = Carbon::Request->parse("POST /asdf?qwert HTTP/1.1\r\nhost: asdf.com\r\n\r\n");
	$success = $success and test_results($test_name => [$req->method, $req->uri, $req->protocol, $req->header('host'), $req->content],
		["POST", '/asdf?qwert', 'HTTP/1.1', 'asdf.com', '']);

	$req = Carbon::Request->parse("POST /asdf?qwert HTTP/1.1\r\ncookie: hello\r\ncookie: world\r\n\r\n");
	$success = $success and test_results($test_name => [$req->method, $req->uri, $req->protocol, $req->header('cookie'), $req->content],
		["POST", '/asdf?qwert', 'HTTP/1.1', 'hello, world', '']);

	$req = Carbon::Request->parse("HEAD /asdf?qwert HTTP/1.1\r\ncookie: hello\r\ncookie: world\r\n\r\ntesting");
	$success = $success and test_results($test_name => [$req->method, $req->uri, $req->protocol, $req->header('cookie'), $req->content],
		["HEAD", '/asdf?qwert', 'HTTP/1.1', 'hello, world', 'testing']);


	warn "$test_name passed\n" if $success;
	return $success
}





warn "request testing:\n";

test_request_compiling;
test_request_parsing;

warn "done\n";

