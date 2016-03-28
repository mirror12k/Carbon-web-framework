#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Data::Dumper;

use lib '..';
use Carbon;
use Carbon::Nanotube;
use Carbon::Anthracite::Plugins::Limestone;
use Carbon::Limestone::Client;


my $client = Carbon::Limestone::Client->new(hostport => 'localhost:2049', username => 'root', password => 'root');
say Dumper $client->create('Limestone::Table=userdb' => {
	columns => {
		username => 'STRING_64',
		password => 'STRING_64',
	},
});


my $srv = Carbon->new(debug => 1);
my $rtr = Carbon::Nanotube->new( debug => 1 );
$rtr->compiler->debug(1);
$srv->router($rtr);
$rtr->compiler->add_plugin(Carbon::Anthracite::Plugins::Limestone->new(hostport => 'localhost:2049', username => 'root', password => 'root'));


$rtr->route_dynamic('/' => '.');

$srv->start_server;
