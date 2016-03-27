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



sub test_route {
	my $success = 1;
	my ($res, $req);
	my $test_name = 'test route';

	my $thr = threads->create(sub {
		my $svr = Carbon->new;
		my $rtr = Carbon::Nanotube->new;
		$svr->router($rtr);
		$rtr->route_dynamic('/' => './test_nanotube_test_route', { suffix => '' });

		$SIG{INT} = sub { $svr->shutdown; };

		$svr->start_server;
	});

	sleep 1;

	my $ua = LWP::UserAgent->new;

	
	$res = $ua->get("http://localhost:2048/hello_world.am");

	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', "hello world!"]);

	$res = $ua->get("http://localhost:2048/non_executable.html");

	$success = $success and test_results($test_name =>
		[$res->code, $res->content],
		['200', "<?perl echo 'this may look like code, but this file is not executable'; ?>\n"]);


	warn "$test_name passed\n" if $success;

	$thr->kill('SIGINT');
	$thr->join;

	return $success
}




warn "nanotube testing:\n";

test_route;

warn "done\n";

