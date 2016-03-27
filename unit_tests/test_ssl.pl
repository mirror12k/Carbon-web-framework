#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use LWP::UserAgent;
use WWW::Mechanize;
use threads;
use Carp;

use lib '..';
use Carbon::SSL;
use Carbon::Fiber;


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




# commands to create the certificate and key:
# openssl genrsa -out key.pem 4096
# openssl req -new -key key.pem -out request.pem
# openssl x509 -req -days 30 -in request.pem -signkey key.pem -out cert.pem


sub test_basic {
	my $success = 1;
	my ($res);
	my $test_name = 'test basic';

	my $thr = threads->create(sub {
		my $svr = Carbon::SSL->new(
			ssl_certificate => 'test_ssl_test_basic/cert.pem',
			ssl_key => 'test_ssl_test_basic/key.pem',
		);
		my $rtr = Carbon::Fiber->new;
		$svr->router($rtr);
		$rtr->route( qr!/.*! => sub {
			my ($rtr, $req, $res) = @_;
			$res //= Carbon::Response->new;
			$res->code('200');
			$res->content('path was: "' . ($req->uri->path // '') . '"');
			return $res
		});

		$SIG{INT} = sub { $svr->shutdown; };

		$svr->start_server;
	});

	sleep 1;

	my $ua = LWP::UserAgent->new;
	$ua->ssl_opts(verify_hostname => 0);
	# to avoid this, we'd need to generate our own CA and then pass it to the ua aswell as sign the ssl key with it

	$res = $ua->get("https://localhost:2048/");

	$success = $success and test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'path was: "/"']);

	$res = $ua->get('https://localhost:2048/hello/world?nope');

	$success = $success and test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'path was: "/hello/world"']);

	warn "$test_name passed\n" if $success;

	$thr->kill('SIGINT');
	$thr->join;


	return $success
}





warn "ssl testing:\n";

test_basic;

warn "done\n";




