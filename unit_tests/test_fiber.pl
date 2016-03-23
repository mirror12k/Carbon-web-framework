#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use LWP::UserAgent;
use WWW::Mechanize;

use lib '..';
use Carbon;
use Carbon::Fiber;
use threads;



sub test_results {
	my ($test_name, $test_values, $expected_values) = @_;

	my $success = 1;
	for my $i (0 .. $#$test_values) {
		if ($test_values->[$i] ne $expected_values->[$i]) {
			warn "$test_name failed: server returned: [$test_values->[$i]], expected: [$expected_values->[$i]]";
			$success = 0;
		}
	}

	return $success
}



sub test_path {
	my $success = 1;
	my ($res, @test_values, @expected_values);
	my $test_name = 'test path';

	my $thr = threads->create(sub {
		my $svr = Carbon->new;
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
	$res = $ua->get("http://localhost:2048/");

	$success = $success and test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'path was: "/"']);

	$res = $ua->get('http://localhost:2048/hello/world?nope');

	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'path was: "/hello/world"']);
	
	warn "$test_name passed\n" if $success;

	$thr->kill('SIGINT');
	$thr->join;


	return $success
}


sub test_basic {
	my $success = 1;
	my ($res, @test_values, @expected_values);
	my $test_name = 'test basic';

	my $thr = threads->create(sub {
		my $svr = Carbon->new;
		my $rtr = Carbon::Fiber->new;
		$svr->router($rtr);
		$rtr->route( qr!/asdf! => sub {
			my ($rtr, $req, $res) = @_;
			$res //= Carbon::Response->new;
			$res->code('200');
			$res->content('success!');
			return $res
		});

		$SIG{INT} = sub { $svr->shutdown; };

		$svr->start_server;
	});

	sleep 1;

	my $ua = LWP::UserAgent->new;

	$res = $ua->get("http://localhost:2048/");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['400', 'Bad Request', 'HTTP/1.1', 'Bad Request']);

	$res = $ua->get("http://localhost:2048/asdf");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'success!']);

	$res = $ua->get("http://localhost:2048/asdf?query=true&a=b#frag");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'success!']);

	$thr->kill('SIGINT');
	$thr->join;

	warn "$test_name passed\n" if $success;

	return $success
}

sub test_hijack {
	my $success = 1;
	my ($res, @test_values, @expected_values);
	my $test_name = 'test hijack';

	my $thr = threads->create(sub {
		my $svr = Carbon->new;
		my $rtr = Carbon::Fiber->new;
		$svr->router($rtr);
		$rtr->route( qr!/asdf.*! => sub {
			my ($rtr, $req, $res) = @_;
			$res //= Carbon::Response->new;
			$res->code('200');
			$res->content('success!');
			return $res
		});
		$rtr->route( qr!/asdf/qwerty! => sub {
			my ($rtr, $req, $res) = @_;
			$res //= Carbon::Response->new('200');
			$res->content($res->content . ' hijack!');
			return $res
		});

		$SIG{INT} = sub { $svr->shutdown; };

		$svr->start_server;
	});

	sleep 1;

	my $ua = LWP::UserAgent->new;

	$res = $ua->get("http://localhost:2048/asdf");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'success!']);

	$res = $ua->get("http://localhost:2048/asdf/nope");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'success!']);

	$res = $ua->get("http://localhost:2048/asdf/qwerty");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'success! hijack!']);

	$thr->kill('SIGINT');
	$thr->join;

	warn "$test_name passed\n" if $success;

	return $success
}


sub test_dir {
	my $success = 1;
	my ($res, @test_values, @expected_values);
	my $test_name = 'test dir';

	my $thr = threads->create(sub {
		my $svr = Carbon->new;
		my $rtr = Carbon::Fiber->new;
		$svr->router($rtr);
		$rtr->route_directory( '/test/' => 'test_fiber_test_dir' );

		$SIG{INT} = sub { $svr->shutdown; };

		$svr->start_server;
	});

	sleep 1;

	my $ua = LWP::UserAgent->new;

	$res = $ua->get("http://localhost:2048/test/index");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'hello index!']);

	$res = $ua->get("http://localhost:2048/test/world.txt");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'hello world!']);

	$res = $ua->get("http://localhost:2048/test/");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['403', 'Forbidden', 'HTTP/1.1', 'Forbidden']);

	$res = $ua->get("http://localhost:2048/");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['400', 'Bad Request', 'HTTP/1.1', 'Bad Request']);

	$thr->kill('SIGINT');
	$thr->join;

	warn "$test_name passed\n" if $success;

	return $success
}



sub test_map {
	my $success = 1;
	my ($res, @test_values, @expected_values);
	my $test_name = 'test map';

	my $thr = threads->create(sub {
		my $svr = Carbon->new;
		my $rtr = Carbon::Fiber->new;
		$svr->router($rtr);
		$rtr->route_map('/qwerty' => '/asdf');
		$rtr->route( qr!/asdf! => sub {
			my ($rtr, $req, $res) = @_;
			$res //= Carbon::Response->new('200');
			$res->content('yes, this is asdf');
			return $res
		});

		$SIG{INT} = sub { $svr->shutdown; };

		$svr->start_server;
	});

	sleep 1;

	my $ua = LWP::UserAgent->new;

	$res = $ua->get("http://localhost:2048/qwerty");
	test_results($test_name =>
		[$res->code, $res->message, $res->protocol, $res->decoded_content],
		['200', 'OK', 'HTTP/1.1', 'yes, this is asdf']);

	$thr->kill('SIGINT');
	$thr->join;

	warn "$test_name passed\n" if $success;

	return $success
}





test_path;
test_basic;
test_hijack;
test_dir;
test_map;

say "done";


