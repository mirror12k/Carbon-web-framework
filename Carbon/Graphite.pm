package Carbon::Graphite;
use strict;
use warnings;

use feature 'say';


# graphite engine

use Carbon::Graphite::Parser;
use Carbon::Graphite::Helper;
use Carbon::Graphite::Template;


sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	$self->templates({});
	$self->helpers({
		template => Carbon::Graphite::Helper->new(
			sub {
				my ($self, $engine, $text) = @_;

				$text =~ s/\A([a-zA-Z0-9_]+(?:::[a-zA-Z0-9_]+)*)\s+?//ms or die 'template requires a text name at start';
				my $name = $1;
				$name =~ s#\\#\\\\#g;
				$name =~ s#'#\\'#g;

				my $code =
"
;\$graphite->set_template('$name' => Carbon::Graphite::Template->new( sub {
my (\$self, \$graphite, \$arg) = \@_;
my \$output = '';
";
				$code .= $engine->compile_graphite ($text);
				$code .=
';return $output
}));
';
				return $code
			}
		),
		foreach => Carbon::Graphite::Helper->new(
			sub {
				my ($self, $engine, $text) = @_;
				$text =~ s/\A\$([a-zA-Z0-9_]+)\b//ms or die 'foreach requires variable name at start';
				say "foreach invoked: $1";
				my $name = $1;
				if ($name eq '_') {
					$name = '$arg';
				} else {
					$name = "\$arg->{$name}";
				}
				my $code =
";foreach my \$arg (\@{$name}) {
";
				$code .= $engine->compile_graphite ($text);
				$code .= "}\n";

				return $code
			}
		),
	});

	return $self
}



sub templates { @_ > 1 ? $_[0]{carbon_graphite__templates} = $_[1] : $_[0]{carbon_graphite__templates} }
sub helpers { @_ > 1 ? $_[0]{carbon_graphite__helpers} = $_[1] : $_[0]{carbon_graphite__helpers} }

sub template {
	my ($self, $name, $value) = @_;
	if (@_ > 2) {
		return $self->templates->{$name} = $value;
	} else {
		return $self->templates->{$name}
	}
}
sub helper {
	my ($self, $name, $value) = @_;
	if (@_ > 2) {
		return $self->helpers->{$name} = $value;
	} else {
		return $self->helpers->{$name}
	}
}

sub compile_graphite_directive {
	my ($self, $block) = @_;
	my $code = $self->code_header;

	$code .= $self->compile_graphite($block);

	$code .= $self->code_tail;
	return $code
}

sub compile_graphite {
	my ($self, $text) = @_;

	say "compiling graphite block: [[[$text]]]";

	my $parser = Carbon::Graphite::Parser->new($text);

	my @helper_stack;
	my $code = '';

	while (my ($type, $text, $raw) = $parser->get_token) {
		if ($type eq 'helper') {
			say "got helper: $text";
			my $block = $parser->get_until_end_helper;
			if (defined $self->helper($text)) {
				$code .= $self->helper($text)->execute($self, $block);
			} else {
				# die "attempt to invoke unknown helper '$text'";
			}
		} elsif ($type eq 'end_helper') {
			die "out of order end helper";
		} elsif ($type eq 'text') {
			$code .= $self->compile_text($text);
		} else {
			die "unknown token type '$type'";
		}
	}
	return $code
}



sub code_header {
	return '
;do {
my $output = "";
'
}

sub code_tail {
	return '
;echo $output;
};
'
}

sub compile_text {
	my ($self, $text) = @_;

	return '' if $text =~ /\A\s*\Z/m;

	$text =~ s/\A\s+/ /m;
	$text =~ s/\s+\Z/ /m;

	my $code = ";\n";

	my $value_regex = qr/
		\$[a-zA-Z0-9_]+| # variable
		\d+| # numeric value
		'[^']*'| # string
		"[^"]*" # string
		/msx;
	while ($text =~ /\G
			(\$[a-zA-Z0-9_]+)|
			\@([a-zA-Z0-9_]+)(?:->
				($value_regex)|
				\[\s*((?:$value_regex(?:,\s*$value_regex)*\s*(?:,\s*)?)?)\]
			)?|
			(.*?((?=[\$\@])|\Z))
			/msgx) {
		my ($var, $inc, $inc_val, $inc_list, $html) = ($1, $2, $3, $4, $5);
		if (defined $var) {
			$code .= "\$output .= ". $self->compile_inc_val($var) .";\n";
		} elsif (defined $inc) {
			if (defined $inc_val) {
				$code .= "\$output .= \$graphite->render_template('$inc' => ". $self->compile_inc_val($inc_val) .");\n";
			} else {
				$code .= "\$output .= \$graphite->render_template('$inc');\n";
			}
		} else {
			$html =~ s/\A\s+/ /m;
			$html =~ s/\s+\Z/ /m;
			$html =~ s#\\#\\\\#g;
			$html =~ s#'#\\'#g;
			$code .= "\$output .= '$html';\n";
		}
	}
	return $code
}

sub compile_inc_val {
	my ($self, $val) = @_;
	if ($val =~ /\A\$([a-zA-Z0-9_]+)\Z/) {
		my $name = $1;
		if ($name ne '_') {
			return "\$arg->{$name}";
		} else {
			return '$arg';
		}
	} elsif ($val =~ /\A\d+\Z/) {
		return $val;
	} elsif ($val =~ /\A'[^']*'\Z/) {
		return $val;
	} elsif ($val =~ /\A"([^"]*)"\Z/) {
		return "'$1'";
	} else {
		die "unknown value to compile: '$val'";
	}
}


sub helper_template_header {
	my ($self) = @_;
}

sub helper_foreach {
	my ($self, $text) = @_;
}

sub helper_if {
	my ($self, $text) = @_;
}
sub helper_elsif {
	my ($self, $text) = @_;
}
sub helper_else {
	my ($self, $text) = @_;
}
sub helper_with {
	my ($self, $text) = @_;
}


1;

