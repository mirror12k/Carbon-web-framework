#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';


use Carbon;
use Carbon::Fiber;
use Carbon::Response;





my $srv = Carbon->new(debug => 1);

my $rtr = Carbon::Fiber->new;
$srv->router($rtr);

# a basic route
$rtr->route(qr!/asdf/.*! => sub {
	my ($rtr, $req, $res) = @_;
	$res //= Carbon::Response->new;
	$res->code('200');
	$res->content('<html><body><h1>hello world!</h1><p>your query was "' . ($req->uri->query // '') . '"</p></body></html>');
	return $res
}, {methods => ['GET']});

# an example addition route which modifies the output of the previous one
$rtr->route('/asdf/qwerty' => sub {
	my ($rtr, $req, $res) = @_;
	$res //= Carbon::Response->new;
	$res->content(($res->content // '') . "LOL HIJACK");
	return $res
});

# an example directory route which serves any files from the current working directory
$rtr->route_directory('/nerf/' => '.');

# an example global route for logging
$rtr->route(qr/.*/ => sub {
		my ($rtr, $req, $res) = @_;
		$res //= Carbon::Response->new(400);
		say $req->uri->path, ' => ', $res->code;
		return $res
});

$srv->start_server;
