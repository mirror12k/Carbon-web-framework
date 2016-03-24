#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Carp;

use lib '..';
use Carbon::Response;




sub test_results {
	my ($test_name, $test_values, $expected_values) = @_;

	my $success = 1;
	for my $i (0 .. $#$test_values) {
		if ($test_values->[$i] ne $expected_values->[$i]) {
			confess "$test_name failed: got: [$test_values->[$i]], expected: [$expected_values->[$i]]";
			$success = 0;
		}
	}

	return $success
}



sub test_response_compiling {
	my $success = 1;
	my ($req);
	my $test_name = 'test response compiling';

	$req = Carbon::Response->new;
	$success = $success and test_results($test_name => [$req->as_string], ["HTTP/1.1 200 OK\r\n\r\n"]);

	$req->code(400);
	$success = $success and test_results($test_name => [$req->as_string], ["HTTP/1.1 400 Bad Request\r\n\r\n"]);

	$req->protocol('HTTP/1.2');
	$req->message('pasta');
	$success = $success and test_results($test_name => [$req->as_string], ["HTTP/1.2 400 pasta\r\n\r\n"]);

	$req->header(magic => 'yes');
	$req->content('completely magic');
	$success = $success and test_results($test_name => [$req->as_string], ["HTTP/1.2 400 pasta\r\nmagic: yes\r\n\r\ncompletely magic"]);

	$req->remove_header('magic');
	$req->header('set-cookie' => ['magic=yes', 'awesome=totally']);
	$req->content(undef);
	$success = $success and test_results($test_name => [$req->as_string],
		["HTTP/1.2 400 pasta\r\nset-cookie: magic=yes\r\nset-cookie: awesome=totally\r\n\r\n"]);


	warn "$test_name passed\n" if $success;

	return $success
}


sub test_response_parsing {
	my $success = 1;
	my ($req);
	my $test_name = 'test response parsing';


	$req = Carbon::Response->parse("HTTP/1.1 200 OK\r\n\r\n");
	$success = $success and test_results($test_name => [$req->protocol, $req->code, $req->message, $req->content],
		['HTTP/1.1', '200', 'OK', '']);

	$req = Carbon::Response->parse("HTTP/1.1 400 Bad Request\r\n\r\nbody");
	$success = $success and test_results($test_name => [$req->protocol, $req->code, $req->message, $req->content],
		['HTTP/1.1', '400', 'Bad Request', 'body']);

	$req = Carbon::Response->parse("HTTP/1.2 400 pasta\r\nmagic: yes\r\n\r\ncompletely magic");
	$success = $success and test_results($test_name => [$req->protocol, $req->code, $req->message, $req->header('magic'), $req->content],
		['HTTP/1.2', '400', 'pasta', 'yes', 'completely magic']);


	warn "$test_name passed\n" if $success;
	return $success
}





warn "response testing:\n";

test_response_compiling;
test_response_parsing;

warn "done\n";

