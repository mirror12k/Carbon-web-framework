#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '..';
use Carbon;
use Carbon::Nanotube;
use Carbon::Anthracite::Plugins::LimestoneClient;


my $srv = Carbon->new(debug => 1);
my $rtr = Carbon::Nanotube->new( debug => 1 );
$rtr->compiler->debug(1);
$srv->router($rtr);
$rtr->compiler->add_plugin(Carbon::Anthracite::Plugins::LimestoneClient->new(hostport => 'localhost:2049'));


$rtr->route_dynamic('/' => '.');

$srv->start_server;
