#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use LWP::UserAgent;
use WWW::Mechanize;
use threads;
use Carp;

use lib '..';
use Carbon;
use Carbon::CGI;


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
	my ($res);
	my $test_name = 'test basic';

	my $thr = threads->create(sub {
		my $svr = Carbon->new;
		my $rtr = Carbon::CGI->new;
		$svr->router($rtr);

		$rtr->route_cgi('/' => './test_cgi_test_basic/', { default_file => 'index.php' });

		$SIG{INT} = sub { $svr->shutdown; };

		$svr->start_server;
	});

	sleep 1;

	my $ua = LWP::UserAgent->new;


	$res = $ua->get("http://localhost:2048/");

	$success = $success and test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'hello php!']);

	$res = $ua->get("http://localhost:2048/get.php");

	$success = $success and test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', "<!doctype html>
<html>
<body>
	<form method=\"GET\">
	<input type=\"text\" name=\"a\" />
	<button>Submit</button>
	</form>
</body>
</html>
"]);

	$res = $ua->get("http://localhost:2048/get.php?a=asdf");

	$success = $success and test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', "<!doctype html>
<html>
<body>
	<p>you entered: asdf</p>
</body>
</html>
"]);

	$res = $ua->get("http://localhost:2048/post.php");

	$success = $success and test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', "<!doctype html>
<html>
<body>
	<form method=\"POST\">
	<input type=\"text\" name=\"a\" />
	<button>Submit</button>
	</form>
</body>
</html>
"]);

	$res = $ua->post("http://localhost:2048/post.php", { a => 'qwertyuiop' });

	$success = $success and test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', "<!doctype html>
<html>
<body>
	<p>you entered: qwertyuiop</p>
</body>
</html>
"]);

	$res = $ua->post("http://localhost:2048/redirect.php", { a => 'qwertyuiop' });

	$success = $success and test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->header('location')],
		['303', 'See Other', 'HTTP/1.1', '/asdf.php']);


	warn "$test_name passed\n" if $success;

	$thr->kill('SIGINT');
	$thr->join;


	return $success
}



warn "cgi testing:\n";

test_basic;

warn "done\n";


