#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';


use lib '..';

use Carbon::SSL;
use Carbon::Nanotube;




# commands to create the certificate and key:
# openssl genrsa -out key.pem 4096
# openssl req -new -key key.pem -out request.pem
# openssl x509 -req -days 30 -in request.pem -signkey key.pem -out cert.pem




my $srv = Carbon::SSL->new(
	debug => 1,
	ssl_certificate => 'cert.pem',
	ssl_key => 'key.pem',
);

my $rtr = Carbon::Nanotube->new( debug => 1 );
$rtr->compiler->debug(1);

$rtr->route_map(qr!/user/(?<user_id>\d+)! => '/view_args');
$rtr->route_dynamic('/' => './../testnanotube/');


$srv->router($rtr);


$SIG{INT} = sub {
	warn "SIGINT received, shutting down...";
	$srv->shutdown();
};

$srv->start_server;
