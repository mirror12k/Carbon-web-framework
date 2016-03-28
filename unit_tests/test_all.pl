#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';


say `./test_uri.pl`;
say `./test_request.pl`;
say `./test_response.pl`;
say `./test_anthracite.pl`;
say `./test_graphite.pl`;
say `./test_fiber.pl`;
say `./test_nanotube.pl`;
say `./test_ssl.pl`;
say `./test_cgi.pl`;
say `./test_limestone.pl`;
say `./test_carbon_stress.pl`;


warn "all tests passed\n";
