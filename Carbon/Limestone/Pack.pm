package Carbon::Limestone::Pack;
use strict;
use warnings;
use base 'Exporter';


our @EXPORT = qw/
pack_value
unpack_value
unpack_value_indexed
/;


sub pack_value {
	my ($value) = @_;
	
	if ('HASH' eq ref $value) { # hash
		my $length = scalar keys %$value;
		die "hash value too long: $value" if 16384 <= $length; # 2^14
		return pack ('n', (1 << 14) | $length) . join ('', map pack_value($_), %$value);
	} elsif ('ARRAY' eq ref $value) { # array
		die "array value too long: $value" if 16384 <= @$value; # 2^14
		return pack ('n', (2 << 14) | @$value) . join ('', map pack_value($_), @$value);
	} elsif ('' eq ref $value) { # string (or number)
		die "string value too long: $value" if 16384 <= length $value; # 2^14
		return pack ('n', (3 << 14) | length ($value)) . $value;
	} else {
		die "unable to pack value of type: ", ref $value;
	}
}


sub unpack_value {
	my ($value) = @_;
	my ($unpacked, $index) = unpack_value_indexed($value);
	return $unpacked
}

sub unpack_value_indexed {
	my ($value, $index) = @_;
	$index //= 0;

	my $n = unpack 'n', substr $value, $index, 2;
	my $len = $n & 0x3fff;
	$index += 2;

	my $ret;
	if (($n >> 14) == 1) { # hash
		my %hash;
		my ($key, $val);
		for (1 .. $len) {
			($key, $index) = unpack_value_indexed($value, $index);
			($val, $index) = unpack_value_indexed($value, $index);
			$hash{$key} = $val;
		}
		$ret = \%hash;
	} elsif (($n >> 14) == 2) { # array
		my @array;
		my $val;
		for (1 .. $len) {
			($val, $index) = unpack_value_indexed($value, $index);
			push @array, $val;
		}
		$ret = \@array;
	} elsif (($n >> 14) == 3) { # string
		my $val = substr $value, $index, $len;
		$index += $len;
		$ret = $val;
	} else {
		die "malformed packed value";
	}
	return $ret, $index
}



1;
