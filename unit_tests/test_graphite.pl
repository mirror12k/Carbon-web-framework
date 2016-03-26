#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use LWP::UserAgent;
use WWW::Mechanize;
use threads;
use Carp;

use lib '..';
use Carbon::Nanotube;
use Carbon::Anthracite::Plugins::Graphite;
use Carbon::Request;
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


sub test_basic {
	my $success = 1;
	my ($res, $req);
	my $test_name = 'test basic';

	my $rtr = Carbon::Nanotube->new;
	$rtr->compiler->add_plugin(Carbon::Anthracite::Plugins::Graphite->new);
	$rtr->init_thread;

	$res = $rtr->execute_dynamic_file('test_graphite_test_basic/hello_world.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	# say "got result: ", $res->as_string;
	$success = $success and test_results($test_name =>
		[$res->code, $res->content =~ s/\A\s*(.*?)\s*\Z/$1/sr],
		['200', '<h1>hello world!</h1>']);

	$res = $rtr->execute_dynamic_file('test_graphite_test_basic/comments.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content =~ s/\A\s*(.*?)\s*\Z/$1/sr],
		['200', 'nothing here']);

	$res = $rtr->execute_dynamic_file('test_graphite_test_basic/test_template.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content =~ s/\A\s*(.*?)\s*\Z/$1/sr],
		['200', '<div><h1>inside of template!</h1></div>']);

	$res = $rtr->execute_dynamic_file('test_graphite_test_basic/test_arguments.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content =~ s/\A\s*(.*?)\s*\Z/$1/sr],
		['200', "<body>
<div><h1>one arg: hello world</h1></div>
<div><h1>more args:</h1><p>item: hello world</p><p>item: test val</p></div>
<div><div type='desc'>name: steve, job: magician</div></div>
</body>"]);

	$res = $rtr->execute_dynamic_file('test_graphite_test_basic/namespaces.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content =~ s/\A\s*(.*?)\s*\Z/$1/sr],
		['200', '<p> it is i, the great huzzah </p>']);
	
	$res = $rtr->execute_dynamic_file('test_graphite_test_basic/if_else.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content =~ s/\A\s*(.*?)\s*\Z/$1/sr],
		['200', '<p>got 5:  it is greater than 1 </p><p>got -5:  it is less than 1 </p><p>got 1:  it is 1 </p>']);

	$res = $rtr->execute_dynamic_file('test_graphite_test_basic/not_graphite.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	$success = $success and test_results($test_name =>
		[$res->code, $res->content =~ s/\A\s*(.*?)\s*\Z/$1/sr],
		['200', "<html>\n<body>\n<p>hello world!</p>\n</body>\n</html>"]); # TODO: fix that stupid newline bug

	warn "$test_name passed\n" if $success;
	return $success
}


sub test_dynamic {
	my $success = 1;
	my ($res, $req);
	my $test_name = 'test dynamic';

	my $rtr = Carbon::Nanotube->new;
	$rtr->compiler->add_plugin(Carbon::Anthracite::Plugins::Graphite->new);
	$rtr->init_thread;

	$res = $rtr->execute_dynamic_file('test_graphite_test_dynamic/template_args.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	# say "got result: ", $res->as_string;
	$success = $success and test_results($test_name =>
		[$res->code, $res->content =~ s/\A\s*(.*?)\s*\Z/$1/sr],
		['200', 'not yet!<p>not yet!</p><div class="dynamic"><p>not yet!</p></div>']);

	$res = $rtr->execute_dynamic_file('test_graphite_test_dynamic/complex_template_args.am', Carbon::Request->new('GET', Carbon::URI->parse('/')));

	# say "got result: ", $res->as_string;
	$success = $success and test_results($test_name =>
		[$res->code, $res->content =~ s/\A\s*(.*?)\s*\Z/$1/sr],
		['200', '<p>hello world!</p><ul><li>example text</li><li>hello world!</li><li>lollollol</li></ul>']);

	warn "$test_name passed\n" if $success;
	return $success
}


warn "graphite testing:\n";

test_basic;
test_dynamic;

warn "done\n";
