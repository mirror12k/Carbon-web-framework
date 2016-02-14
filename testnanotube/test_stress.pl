#!/usr/bin/perl
use strict;
use warnings;

use feature 'say';

use LWP::Simple;
use IO::Socket::INET;


# get a sample of the index page for reference
my $data = get 'http://localhost:2048';

# create multiple parallel processes
for (1 .. 20) {
	fork or last
}





# request the page as much as possible
for (1 .. 1000) {
	say "$_";

	# # basic socket send and readline
	# my $sock = IO::Socket::INET->new(PeerHost => 'localhost:2048');
	# $sock->send("GET / HTTP/1.1\r\n\r\n");
	# warn "failed" unless <$sock> =~ /HTTP\/1.1 200 OK/;
	# $sock->close;

	# LWP get and compare
	my $res = get 'http://localhost:2048';
	if ($res ne $data) {
		warn "error: got $res";
	}
}

