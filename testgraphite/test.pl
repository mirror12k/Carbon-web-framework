#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '..';
use Carbon;
use Carbon::Nanotube;
use Carbon::Anthracite::Plugins::Graphite;


my $srv = Carbon->new(debug => 1);
my $rtr = Carbon::Nanotube->new(debug => 1);
$srv->router($rtr);

$rtr->compiler->debug(1);
$rtr->compiler->add_plugin(Carbon::Anthracite::Plugins::Graphite->new);


$rtr->route_dynamic('/' => './html/');


$SIG{INT} = sub {
	warn "SIGINT received, shutting down...";
	$srv->shutdown();
};


$srv->start_server;
