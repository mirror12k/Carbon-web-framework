#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';
use File::Map qw/ map_file remap unmap /;
use FreezeThaw qw/ freeze thaw /;


map_file my $file, 'test.db', '+<';

remap $file, 4 * 100;
# $file .= 'asdf';
substr $file, 0, 4 * 100, 'asdf' x 100;

unmap $file;

my $data = {
	type => 'get',
	where => {
		cost => 15,
		sold => '$ > 100',
	},
};
say freeze ($data);
say length freeze ($data);

