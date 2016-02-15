#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';


use lib '..';

use Carbon;
use Carbon::CGI;



my $srv = Carbon->new( debug => 1 );
my $rtr = Carbon::CGI->new( debug => 1 );
$srv->router($rtr);

$rtr->route_cgi('/' => './cgi-bin/');

$srv->start_server;
