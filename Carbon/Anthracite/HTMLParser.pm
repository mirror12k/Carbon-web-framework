package Carbon::Anthracite::HTMLParser;
use strict;
use warnings;

use feature 'say';


sub new {
	my ($class, $text) = @_;
	my $self = bless { text => $text, position => 0 }, $class;

	return $self
}


sub get_token {
	my ($self) = @_;
	return if $self->{position} >= length $self->{text};

	# my $text = $self->{text};
	# pos($self->{text}) = $self->{position};

	while ($self->{text} =~
			m/\G
				(<([!\/]?[a-zA-Z]+\b)(.*?)>)| # match a start tag, end tag, or comment
				(<\?([a-zA-Z]+)(.*?)(?:\?>|\Z(?!\s)))| # match a directive
											# this is a fix for some inexplicable behavior where the 
											# \Z will match on the newline before the end of the string
				(.+?)(?:(?=<)|\Z) # match regular text
			/smxg) {
		my ($tag, $tag_type, $tag_data, $directive, $directive_type, $directive_data, $text) = ($1, $2, $3, $4, $5, $6, $7);
		# say "debug: ", pos $self->{text};
		# $self->{position} = pos $self->{text};
		if (defined $tag) {
			return tag => $tag, $tag_type, $tag_data
		} elsif (defined $directive) {
			return directive => $directive, $directive_type, $directive_data
		} else {
			return text => $text
		}
	}
	return
}


1;

