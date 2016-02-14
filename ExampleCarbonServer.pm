#!/usr/bin/env perl
package ExampleCarbonServer;
use parent 'Carbon';

use strict;
use warnings;

use feature 'say';

use Carbon::Request;
use Carbon::Response;


our $EXAMPLECARBONSERVER_DEBUG_VALUE = 1 + $Carbon::CARBON_DEBUG_VALUE;


sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);

	# a trick so that we parse our own routes
	$self->router($self);
	
	return $self
}

sub init_thread {
	my ($self) = @_;
	# do nothing
}

# override the abstract method to produce a simple Carbon::Response
sub execute {
	my ($self, $req) = @_;

	# say "got a full request: \n$data";
	# say "request: ", $req->uri;

	my $res;

	if ($req->uri->path eq '/') {
		$res = Carbon::Response->new('200');
		if ($req->method eq 'GET') {
			$res->content('<html><body><form method="POST"><input type="text" name="test" /><button>submit</button></form></body></html>');
			$res->header('Content-Type' => 'text/html');
		} else {
			$res->content($req->content);
			$res->header('Content-Type' => 'text/plain');
		}
	} else {
		$res = Carbon::Response->new('404');
		$res->content('not found');
		$res->header('Content-Type' => 'text/plain');
	}

	$res->protocol('HTTP/1.1');
	$res->header('Content-Length' => length $res->content);

	if (not $res->is_error) {
		$res->header('Connection' => 'keep-alive');
	} else {
		$res->header('Connection' => 'close');
	}

	return $res
}



sub main {
	my $srv = ExampleCarbonServer->new (debug => 1);
	$srv->start_server;
}

caller or main(@ARGV)

