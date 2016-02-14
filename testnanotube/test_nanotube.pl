#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';


use lib '..';

use Carbon;
use Carbon::Nanotube;





my $srv = Carbon->new(debug => 1);

my $rtr = Carbon::Nanotube->new( debug => 1 );
$rtr->compiler->debug(1);

$rtr->pre_compile_dynamic('include');
$rtr->pre_compile_dynamic('index.am');

$rtr->pre_include_dynamic('include');

$rtr->route_map(qr!/user/(?<user_id>\d+)! => '/view_args');
$rtr->route_dynamic('/' => '.');


$srv->router($rtr);


$SIG{INT} = sub {
	warn "SIGINT received, shutting down...";
	$srv->shutdown();
};

$srv->start_server;
