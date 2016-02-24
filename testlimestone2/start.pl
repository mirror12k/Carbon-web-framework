#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';


use lib '..';

use Carbon::Limestone;




# commands to create the certificate and key:
# openssl genrsa -out key.pem 4096
# openssl req -new -key key.pem -out request.pem
# openssl x509 -req -days 30 -in request.pem -signkey key.pem -out cert.pem




my $srv = Carbon::Limestone->new(
	debug => 1,
	ssl_certificate => 'cert.pem',
	ssl_key => 'key.pem',
	port => 2049,
	database_filepath => 'mydb',
);


$SIG{INT} = sub {
	warn "SIGINT received, shutting down...";
	$srv->shutdown();
};

$srv->start_server;