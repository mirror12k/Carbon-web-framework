#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Carp;

use lib '..';
use Carbon::URI;




sub test_results {
	my ($test_name, $test_values, $expected_values) = @_;

	my $success = 1;
	for my $i (0 .. $#$test_values) {
		if ($test_values->[$i] ne $expected_values->[$i]) {
			confess "$test_name failed: server returned: [$test_values->[$i]], expected: [$expected_values->[$i]]";
			$success = 0;
		}
	}

	return $success
}



sub test_uris {
	my $success = 1;
	my ($uri);
	my $test_name = 'test path';

	$uri = Carbon::URI->new;
	$uri->path('/');
	$success = $success and test_results($test_name => [$uri->as_string], ['/']);

	$uri->protocol('http:');
	$uri->host('google.com');
	$success = $success and test_results($test_name => [$uri->as_string], ['http://google.com/']);

	$uri->query('a=b&asdf=qwerty');
	$uri->fragment('magic');
	$success = $success and test_results($test_name => [$uri->as_string], ['http://google.com/?a=b&asdf=qwerty#magic']);

	$uri->path('/test/asdf');
	$uri->query(undef);
	$success = $success and test_results($test_name => [$uri->as_string], ['http://google.com/test/asdf#magic']);

	$uri->port('245');
	$uri->protocol('magic:');
	$success = $success and test_results($test_name => [$uri->as_string], ['magic://google.com:245/test/asdf#magic']);

	$uri->path(undef);
	$uri->fragment(undef);
	$success = $success and test_results($test_name => [$uri->as_string], ['magic://google.com:245']);


	$uri = Carbon::URI->parse('/');
	$success = $success and test_results($test_name => [$uri->path], ['/']);

	$uri = Carbon::URI->parse('http://google.com/');
	$success = $success and test_results($test_name => [$uri->protocol, $uri->host, $uri->path], ['http:', 'google.com', '/']);

	$uri = Carbon::URI->parse('http://google.com/?a=b&asdf=qwerty#magic');
	$success = $success and test_results($test_name => [$uri->protocol, $uri->host, $uri->path, $uri->query, $uri->fragment],
		['http:', 'google.com', '/', 'a=b&asdf=qwerty', 'magic']);

	$uri = Carbon::URI->parse('http://google.com/test/asdf#magic');
	$success = $success and test_results($test_name => [$uri->protocol, $uri->host, $uri->path, $uri->fragment],
		['http:', 'google.com', '/test/asdf', 'magic']);

	$uri = Carbon::URI->parse('magic://google.com:245/test/asdf#magic');
	$success = $success and test_results($test_name => [$uri->protocol, $uri->host, $uri->port, $uri->path, $uri->fragment],
		['magic:', 'google.com', '245', '/test/asdf', 'magic']);

	$uri = Carbon::URI->parse('magic://google.com:245');
	$success = $success and test_results($test_name => [$uri->protocol, $uri->host, $uri->port],
		['magic:', 'google.com', '245']);

	$uri = Carbon::URI->parse('../asdf');
	$success = $success and test_results($test_name => [$uri->path],
		['../asdf']);
	$uri = Carbon::URI->parse('//asdf.com');
	$success = $success and test_results($test_name => [$uri->host, $uri->path],
		['asdf.com', '']);



	warn "$test_name passed\n" if $success;

	return $success
}

warn "uri testing:\n";

test_uris;

warn "done\n";

