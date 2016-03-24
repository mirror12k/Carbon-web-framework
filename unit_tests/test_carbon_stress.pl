#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use LWP::UserAgent;
use WWW::Mechanize;
use Thread::Pool;
use threads;

use lib '..';
use Carbon;
use Carbon::Fiber;



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



sub test_linear_stress {
	my $success = 1;
	my ($res);
	my $test_name = 'test linear stress';

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

	my @result_values;
	my @expected_values;

	for (0 .. 200) {
		my $path = join '', map { (qw/ a b c d e f g h A X Y Z 1 2 3 4 + ! _ - /)[int (20 * rand)] } 0 .. int (50 * rand);
		# say "debug path : $path";
		$res = $ua->get("http://localhost:2048/$path");
		push @result_values, $res->code, $res->decoded_content;
		push @expected_values, '200', "path was: \"/$path\"";
	}

	$success = $success and test_results($test_name =>
		\@result_values,
		\@expected_values);

	warn "$test_name passed\n" if $success;

	$thr->kill('SIGINT');
	$thr->join;


	return $success
}



sub test_threaded_stress {
	my $success = 1;
	my ($res);
	my $test_name = 'test threaded stress';

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


	my @result_values;
	my @expected_values;

	my $test_count = 2000;
	my $pool = Thread::Pool->new( {workers => 10, maxjobs => $test_count, do => sub {
		my $path = shift;
		my $ua = LWP::UserAgent->new;
		my $res = $ua->get("http://localhost:2048/$path");
		return $path, $res->code, $res->decoded_content;
	}} );


	for (0 .. $test_count) {
		my $path = join '', map { (qw/ a b c d e f g h A X Y Z 1 2 3 4 + ! _ - /)[int (20 * rand)] } 0 .. int (50 * rand);
		my (undef) = $pool->job($path);
	}

	for (0 .. $test_count) {
		my @results = $pool->result_any;
		# warn "debug got result: ", @results;
		my $path = shift @results;
		push @result_values, @results;
		push @expected_values, '200', "path was: \"/$path\"";
	}

	$success = $success and test_results($test_name =>
		\@result_values,
		\@expected_values);

	$pool->shutdown;

	warn "$test_name passed\n" if $success;

	$thr->kill('SIGINT');
	$thr->join;


	return $success
}




test_linear_stress;
test_threaded_stress;


say 'done';

