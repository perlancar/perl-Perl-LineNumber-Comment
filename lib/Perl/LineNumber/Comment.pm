package Perl::LineNumber::Comment;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use warnings;
use strict;

use Exporter qw(import);
our @EXPORT_OK = qw(
                       add_line_number_comments_to_perl_source
);

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Add line number to Perl source as comment',
};

sub _line_has {
    my ($line, $children, $sub) = @_;
    for my $child (@$children) {
        my $location = $child->location;
        next unless $location->[0] == $line;
        next unless $sub->($child);
        return 1;
    }
    0;
}

sub _line_has_class {
    my ($line, $children, $class) = @_;
    _line_has($line, $children, sub { ref($_[0]) eq $class });
}

sub _line_has_END {
    my ($line, $children) = @_;
    _line_has($line, $children, sub { ref($_[0]) eq 'PPI::Token::Separator' && $_[0]->content eq '__END__' });
}

sub _process_children {
    my ($level, $args, $lines, $node) = @_;
    return unless $node->can("children");

    my $every     = $args->{every};
    my $linum_col = $args->{column};
    my $fmt       = $args->{format};

    my @children = $node->children;
    my $i = 0;
    while ($i < @children) {
        my $child = $children[$i];

        my $location = $child->location;
        my ($line, undef, $col) = @$location;
        {
            my $class = ref($child);
            my $content = $child->content;
            #use DD; dd (("  " x $level) . "D: [$location->[0], $location->[1], $location->[2]] $i $class <$content>");

            # only insert comment after $EVERY line
            last unless $line % $every == 0;

            # insert after newline
            last unless $class eq 'PPI::Token::Whitespace' && $content =~ /\A\R\z/;

            # BUG HereDoc doesn't print content?

            # don't insert at __END__ line
            last if _line_has_END($line, \@children);

            # don't insert width excess $COLUMN setting

            #   we want to vertically align line number comment; but PPI reports
            #   column that are not reset after \n, so that's useless.
            #my $col_after_child = $col + length($content); # XXX use visual width

            #   so we just use the lines from original source for now
            my $col_after_child = length($lines->[$line-1]); # XXX use visual width
            next if $col_after_child >= $linum_col;

            # don't insert after a comment
            next if $i && ref($children[$i-1]) eq 'PPI::Token::Comment' && $children[$i-1]->content !~ /\R/;

            #say "  <-- insert ($col_after_child)";

            #my $el_ws = bless {
            #    _location => [$line, $col_after_child, $col_after_child, $location->[3], undef],
            #    content => (" " x ($linum_col - $col_after_child)),
            #}, 'PPI::Token::Whitespace';
            #my $el_comment = bless {
            #    _location => [$line, $linum_col, $linum_col, $location->[3], undef],
            #    content => sprintf($fmt, $line) . "\n",
            #}, 'PPI::Token::Comment';

            #splice @{ $node->{children} }, $i, 1, $el_ws, $el_comment;
            #$i += 1;
            #splice @{ $node->{children} }, $i, 1, $el_comment;

            $lines->[$line-1] =~ s/\R\z//;
            $lines->[$line-1] .=
                (" " x ($linum_col - $col_after_child)) .
                sprintf($fmt, $line) . "\n";
        }

        _process_children($level+1, $args, $lines, $child);
        $i++;
    }
}

$SPEC{add_line_number_comments_to_perl_source} = {
    v => 1.1,
    args => {
        source => {
            schema => 'str*',
            cmdline_src => 'stdin_or_file',
            req => 1,
            pos => 0,
        },
        format => {
            schema => 'str*',
            default => ' # line %d',
        },
        column => {
            schema => 'posint*',
            default => 80,
        },
        every => {
            schema => 'posint*',
            default => 5,
        },
    },
    result_naked => 1,
};
sub add_line_number_comments_to_perl_source {
    my %args = @_;
    $args{every}  //= 5;
    $args{column} //= 80;
    $args{format} //= ' # line %d';

    require PPI::Document;
    my $doc = PPI::Document->new(\$args{source});

    # provide an easier columns
    my $lines = [split /^/m, $args{source}];

    # $doc->find stops after some nodes?
    _process_children(0, \%args, $lines, $doc);

    #require PPI::Dumper; PPI::Dumper->new($doc)->print;
    #return "$doc";

    join "", @$lines;
}

1;
# ABSTRACT:

=for Pod::Coverage ^(.+)$

=head1 SYNOPSIS

Content of F<sample.pl>:

 #!/usr/bin/env perl

 use 5.010001;
 use strict;
 use warnings;

 print "Hello, world 1!";
 print "Hello, world 2!";                   # a comment
 print "A multiline
 string";

 print <<EOF;
 A heredoc (not shown in node->content).

 Line three.
 EOF

 exit 0;

 __END__
 one
 two
 three

In your code:

 use File::Slurper qw(read_text);
 use Perl::LineNumber::Comment qw(add_line_number_comments_to_perl_source);

 my $source = read_text('sample.pl');
 print add_line_number_comments_to_perl_source(source => $source);

Output:

 #!/usr/bin/env perl

 use 5.010001;
 use strict;
 use warnings;                                                                   # line 5

 print "Hello, world 1!";
 print "Hello, world 2!";                   # a comment
 print "A multiline
 string";                                                                        # line 10

 print <<EOF;
 A heredoc (not shown in node->content).

 Line three.
 EOF

 exit 0;

 __END__
 one
 two
 three

With this code:

 print add_line_number_comments_to_perl_source(source => $source, every=>1);

Output:

 #!/usr/bin/env perl
                                                                                 # line 2
 use 5.010001;                                                                   # line 3
 use strict;                                                                     # line 4
 use warnings;                                                                   # line 5
                                                                                 # line 6
 print "Hello, world 1!";                                                        # line 7
 print "Hello, world 2!";                   # a comment
 print "A multiline
 string";                                                                        # line 10
                                                                                 # line 11
 print <<EOF;                                                                    # line 12
 A heredoc (not shown in node->content).

 Line three.
 EOF
                                                                                 # line 17
 exit 0;                                                                         # line 18
                                                                                 # line 19
 __END__
 one
 two
 three


=head1 SEE ALSO
