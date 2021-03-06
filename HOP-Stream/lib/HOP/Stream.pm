package HOP::Stream;

use warnings;
use strict;
use Carp;

use base 'Exporter';
our @EXPORT_OK = qw(
  cutsort
  drop
  filter
  head
  insert
  is_node
  iterator_to_stream
  stream_to_iterator
  list2stream
  stream2list
  list_to_stream
  append
  merge
  node
  pick
  promise
  show
  tail
  take
  discard
  transform
  upto
  upfrom
  EMPTY
  is_empty
  fuse
  uniq
  discard
  fold
  constants
  dieOnEmpty
  warnOnEmpty
  genstream
  stream_length
);

#our %EXPORT_TAGS = ( 'all' => \@EXPORT_OK );
# don't export dieOnEmpty or warnOnEmpty with :all
my %not_in_all = ( warnOnEmpty => 1, dieOnEmpty => 1 );
my @all_but = grep { !$not_in_all{$_} } @EXPORT_OK;
our %EXPORT_TAGS = ( 'all' => \@all_but );

=head1 NAME

HOP::Stream - "Higher Order Perl" streams

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';

our $_dieOnEmpty = 0;
my $_warnOnEmpty = 0;

# handle warnOnEmpty and dieOnEmpty, which are not functions
sub import {
   my $package = shift;
   my %routines = map { $_ => 1 } @_;
   $_dieOnEmpty = 1 if $routines{dieOnEmpty};
   $_warnOnEmpty = 1 if $routines{warnOnEmpty};
   HOP::Stream->export_to_level(1, 0, @_);
}

=head1 SYNOPSIS

=head1 DESCRIPTION

This package is based on the Stream.pm code from the book "Higher Order Perl",
by Mark Jason Dominus.

A stream is conceptually similar to a linked list. However, we may have an
infinite stream. As infinite amounts of data are frequently taxing to the
memory of most systems, the tail of the list may be a I<promise>. A promise,
in this context, is merely a promise that the code will compute the rest of
the list if necessary. Thus, the rest of the list does not exist until
actually needed.

The documentation here is not complete.  See "Higher Order Perl" by Mark
Dominus for a full explanation.  Further, this is B<ALPHA> code.  Patches
and suggestions welcome.

=head1 EXPORT

The following functions may be exported upon demand.  ":all" may be specified
if you wish everything exported.

=over 4

=item * constants

=item * cutsort

=item * drop

=item * filter

=item * fold

=item * head

=item * insert

=item * iterator_to_stream

=item * list2stream

=item * list_to_stream

=item * append

=item * fuse

=item * uniq

=item * merge

=item * node

=item * promise

=item * show

=item * stream_to_iterator

=item * stream2list

=item * tail

=item * take

=item * discard

=item * transform

=item * upto

=item * upfrom

=item * fold

=back

=head1 FUNCTIONS

=head2 node

 my $stream = node( $head, $tail );

The fundamental constructor for streams. Returns a node, which defines a 
stream. 

The tail of a node may be either another node, or a I<promise> to compute 
the actual tail when needed.

=cut

sub node {
    my ( $h, $t ) = @_;
    bless [ $h, $t ], __PACKAGE__;
}

##############################################################################

# For internal use only.
# Working around inherent problem with "odd" streams:
# http://homepages.inf.ed.ac.uk/wadler/papers/lazyinstrict/lazyinstrict.ps
# http://srfi.schemers.org/srfi-40/srfi-40.html
# Used by tail() to store error encountered when fulfilling a promise,
# so that program doesn't fail until head() is called to fetch the result. 
my $_error = [];
sub is_error { ref($_[0]) eq 'ARRAY' and $_[0] eq $_error }

=head2 head

  my $head = head( $stream );

or

  my $head = $stream->head;

This function returns the head of a stream.

=cut

sub head {
    my ($s) = @_;
    die $s->[1] if ref($s) && is_error($s->[0]); # ref() prevents
                                                 # autovivification of $s
    if (is_empty($s)) {
       croak "Attempt to call head() on empty stream" if $_dieOnEmpty;
       carp "Attempt to call head() on empty stream" if $_warnOnEmpty;
    }
    return undef unless is_node($s);
    $s->[0];
}

##############################################################################

=head2 tail

 my $tail = tail( $stream ); 

or

 my $tail = $stream->tail;

Returns the I<tail> of a stream.

=cut

sub tail {
    my ($s) = @_;
    if (is_empty($s)) {
       croak "Attempt to call tail() on empty stream" if $_dieOnEmpty;
       carp "Attempt to call tail() on empty stream" if $_warnOnEmpty;
    }
    return undef unless is_node($s);
    
    if ( is_promise( $s->[1] ) ) {
       $s->[1] = eval { $s->[1]->() };
       $s->[1] = node($_error, $@) if $@; # store error if encountered
    }
    $s->[1];
}

##############################################################################

=head2 EMPTY

Constant designating the empty stream. Equivalent to C<undef>.

=cut

sub EMPTY () { undef };

##############################################################################

=head2 is_empty

   my $head = $stream->head unless is_empty($stream);

Returns true if $stream is empty.

=cut

sub is_empty { not defined $_[0] }

##############################################################################

=head2 is_node

  if ( is_node($tail) ) {
     ...
  }

Returns true if the tail of a node is a node. Generally this function is
used internally.

=cut

sub is_node {
    # Note that this is *not* bad code.  Nodes aren't really objects.  They're
    # merely being blessed to ensure that we can disambiguate them from array
    # references.
    UNIVERSAL::isa( $_[0], __PACKAGE__ );
}

##############################################################################

=head2 is_promise

  if ( is_promise($tail) ) {
     ...
  }

Returns true if the tail of a node is a promise. Generally this function is
used internally.

=cut

sub is_promise {
    UNIVERSAL::isa( $_[0], 'CODE' );
}

##############################################################################

=head2 promise

  my $promise = promise { ... };

A utility function with a code prototype (C<< sub promise(&); >>) allowing one
to specify a coderef with curly braces and omit the C<sub> keyword.

=cut

sub promise (&) { $_[0] }

##############################################################################

=head2 show

 show( $stream, [ $number_of_nodes ] ); 

This is a debugging function that will return a text representation of
C<$number_of_nodes> of the stream C<$stream>.

Omitting the second argument will print all elements of the stream. This is
not recommended for infinite streams (duh).

The elements of the stream will be separated by the current value of C<$">.

=cut

sub show {
    my ( $s, $n ) = @_;
    my $show = '';
    while ( $s && ( !defined $n || $n-- > 0 ) ) {
        $show .= head($s) . $";
        $s = tail($s);
    }
    return $show;
}

##############################################################################

=head2 pick

  my $pick = $stream->pick($n)

Returns the element of a stream at index n, starting with index 0.

=cut

sub pick {
   my ($s, $n) = @_;

   return if is_empty($s);

   for (1 .. $n) {
      $s = $s->tail;
      return if is_empty($s);
   }
   return $s->head;
}

##############################################################################

=head2 take

   my $taken = take($stream, $n);

   or

   my $taken = $stream->take($n);

Returns a new stream consisting of the first n elements of $stream.   

=cut

sub take {
   my ($s, $n) = @_;
   if ($n == 0 or is_empty($s)) {
      return EMPTY;
   } else {
      return node($s->head, take($s->tail, ($n - 1)));
   }
}

##############################################################################

=head2 discard

   my $newstream = discard($stream, $n);

   # or

   my $newstream = $stream->discard($n);

Creates a new stream from the original stream with its first n elements
discarded.

=cut

sub discard {
   my ($s, $n) = @_;
   while (!is_empty($s) and $n > 0) {
      $s = $s->tail;
      $n--;
   }
   return $s;
}

##############################################################################

=head2 drop

  my $head = drop( $stream );

This is the C<shift> function for streams. It returns the head of the stream
and and modifies the stream in-place to be the tail of the stream.

=cut

sub drop {
    my $h = head( $_[0] );
    $_[0] = tail( $_[0] );
    return $h;
}

##############################################################################

=head2 transform

  my $new_stream = transform { $_[0] * 2 } $old_stream;

This is the C<map> function for streams. It returns a new stream.

=cut

sub transform (&$) {
    my $f = shift;
    my $s = shift;
    return if is_empty($s);
    node( $f->( head($s) ), promise { transform ( $f, tail($s) ) } );
}

##############################################################################

=head2 filter

  my $new_stream = filter { $_[0] % 2 } $old_stream;

This is the C<grep> function for streams. It returns a new stream.

=cut

sub filter (&$) {
    my $f = shift;
    my $s = shift;
    until ( is_empty($s) || $f->( head($s) ) ) {
        drop($s);
    }
    return EMPTY if is_empty($s);
    return node( head($s), promise { filter ( $f, tail($s) ) } );
}

##############################################################################

=head2 fuse

   my $fuse = fuse( $stream1, $stream2, $cmp );

   # or

   my $fuse = fuse( $stream1, $stream2 );

Takes two streams, assumed to be in sorted order, and returns a new stream, 
also in sorted order, consisting of all the elements of the original two 
streams. The third, optional, parameter specifies a comparison operator for 
sorting; if omitted, C<<sub { $_[0] < $_[1] }>> (numeric sort order) is used.

=cut

sub fuse {
    my ( $s1, $s2, $cmp ) = @_;
    $cmp ||= sub { $_[0] < $_[1] };
    return $s1 if is_empty($s2);
    return $s2 if is_empty($s1);
    my ( $h1, $h2 ) = ( $s1->head, $s2->head );
    if ( $cmp->($h2, $h1) ) {
        node( $h2, promise { fuse( $s1, $s2->tail, $cmp ) } );
    } else {
        node( $h1, promise { fuse( $s1->tail, $s2, $cmp ) } );
    }
}

##############################################################################

=head2 uniq

   my $uniq = uniq($stream, sub { $_[0] eq $_[1] })

   # or
   
   my $uniq = $stream->uniq( sub { $_[0] eq $_[1] } );

Creates a new stream from the input stream, removing duplicate elements.
The optional second parameter is an equality operator for determining whether
two elements are duplicates. If omitted, C<sub { $_[0] == $_[1] }> (numeric
equality) is used.

=cut

sub uniq {
   my ($s, $eq) = @_;
   $eq ||= sub { $_[0] == $_[1] };
   if (is_empty($s)) {
      return EMPTY;
   } elsif (is_empty($s->tail)) {
      return $s;
   } elsif ($eq->($s->head, $s->tail->head)) {
      return uniq($s->tail, $eq);
   } else {
      return node($s->head, promise { uniq($s->tail, $eq) });
   }
}


##############################################################################

=head2 merge

  my $merged_stream = merge( $stream1, $stream2 );

Preserved for backwards-compatibility. Use C<fuse()> instead.

This function takes two streams assumed to be in sorted order and merges them
into a new stream, also in sorted order.

=cut

sub merge {
    my ( $S, $T ) = @_;
    return $T unless $S;
    return $S unless $T;
    my ( $s, $t ) = ( head($S), head($T) );
    if ( $s > $t ) {
        node( $t, promise { merge( $S, tail($T) ) } );
    }
    elsif ( $s < $t ) {
        node( $s, promise { merge( tail($S), $T ) } );
    }
    else {
        node( $s, promise { merge( tail($S), tail($T) ) } );
    }
}

##############################################################################

=head2 append

  my $merged_stream = append( $stream1, $stream2 );

This function takes a list of streams and attaches them together head-to-tail
into a new stream.

=cut

sub append {
    my (@streams) = @_;

    while (@streams) {
        my $h = drop( $streams[0] );
        return node( $h, promise { append(@streams) } ) if not is_empty($h);
        shift @streams;
    }
    return EMPTY;
}

##############################################################################

=head2 list2stream

  my $stream = list2stream(@list);

Converts a list into a stream, lazily.

Replaces the non-lazy C<list_to_stream()>, which is kept for backwards-
compatibility. Unlike C<list_to_stream()>, C<list2stream()> does not 
append a stream when it finds a node or promise in the final position.
This enables you to convert a list of streams into a stream of streams,
or a list of coderefs into a stream of coderefs.

=cut
sub list2stream {

   my @list = @_;
   return EMPTY unless @list;
   my $head = shift @list;
   my $tail = @list ? promise { list2stream(@list) } : undef;
   return node($head, $tail);
}   

##############################################################################

=head2 stream2list

 my @list = stream2list($stream); 

 # or

 my @list = $stream->stream2list;

Converts a stream to a list. If you call this on an infinite stream, it 
may take a long time and use a lot of memory.

=cut

sub stream2list {

   my $s = $_[0];
   my @list;
   while ($s) {
      push @list, $s->head;
      $s = $s->tail;
   }
   return @list;
}

##############################################################################

=head2 list_to_stream

  my $stream = list_to_stream(@list);

Kept for backwards-compatibility. Use C<list2stream> instead.

Converts a list into a stream, non-lazily.  The final item of C<@list> should 
be a promise or another stream.  Thus, to generate the numbers one through 
ten, one could do this:

 my $stream = list_to_stream( 1 .. 9, node(10, undef) );
 # or
 my $stream = list_to_stream( 1 .. 9, node(10) );

=cut

sub list_to_stream {
    my $node = pop;
    $node = node($node) unless is_node($node);    

    while (@_) {
        my $item = pop;
        $node = node( $item, $node );
    }
    $node;
}

##############################################################################

=head2 iterator_to_stream

  my $stream = iterator_to_stream($iterator);

Converts an iterator into a stream.  An iterator is merely a code reference
which, when called, keeps returning elements until there are no more elements,
at which point it returns "undef".

=cut

sub iterator_to_stream {
    my $it = shift;
    my $v  = $it->();
    return unless defined $v;
    node( $v, sub { iterator_to_stream($it) } );
}

##############################################################################

=head2 stream_to_iterator

  my $iterator = stream_to_iterator($stream)

  # or

  my $iterator = $stream->iterator_to_stream

Converts a stream to an iterator.

=cut

sub stream_to_iterator {
   my $s = $_[0];
   my $it = sub { my $h; 
                  if (defined $s) { $h = $s->head; $s->drop } 
                  return $h };
   return $it;
}

##############################################################################

=head2 upto

  my $stream = upto($from_num, $to_num);

Given two numbers, C<$from_num> and C<$to_num>, returns an iterator which will
return all of the numbers between C<$from_num> and C<$to_num>, inclusive.

=cut

sub upto {
    my ( $m, $n ) = @_;
    return if $m > $n;
    node( $m, promise { upto( $m + 1, $n ) } );
}

##############################################################################

=head2 upfrom

  my $stream = upfrom($num);

Similar to C<upto>, this function returns a stream which will generate an 
infinite list of numbers starting from C<$num>.

=cut

sub upfrom {
    my ($m) = @_;
    node( $m, promise { upfrom( $m + 1 ) } );
}

##############################################################################

=head constants

   my $stream = constants( @list );

Returns an infinite stream with the members of C<@list> as its elements, 
repeating in succession forever.  

=cut

sub constants {
   my @args = @_;
   my $first = shift @args;
   push @args, $first;
   return node($first, promise { constants(@args) });
}

##############################################################################

=head2 fold

   my $folded = $stream->fold($sub, $base);

   # or

   my $folded = fold($stream, $sub, $base);

fold() applies the coderef C<$sub> to C<$base> and the first element of 
C<$stream> to compute a new C<$base>, then applies C<$sub> to the new
C<$base> and the next element of C<$stream>, and so forth, accumulating
a value that is returned when the end of C<$stream> is reached.

For example, to sum all the elements in C<$stream> you could write:

   my $sum = $stream->fold(sub { $_[0] + $_[1] }, 0);

fold() should not be called on an infinite stream.   

=cut

sub fold {
   my ($stream, $sub, $base) = @_;
   while ($stream) {
      $base = $sub->($base, $stream->head);
      $stream = $stream->tail;
   }
   return $base;
}

##############################################################################

=head2 genstream

   my $stream = genstream { ... } $base;

Generates a new stream beginning with $base, computing successive elements
by applying the specified procedure to each element in turn. For example, 
a stream of floats approximating the golden ration phi may be defined as

   my $golden = genstream { 1 / $_[0] + 1 } 1;

=cut   

sub genstream (&$) {
   my ($proc, $base) = @_;
   return node($base, promise { genstream($proc, $proc->($base)) });
}

##############################################################################

=head2 stream_length

   my $length = $s->stream_length;

   # or

   my $length = stream_length($s);

Returns the length of a finite stream. Will never return if called on an
infinite stream.

=cut

sub stream_length {
   my $s = $_[0];
   my $length = 0;
   while ($s) {
      $length++;
      $s = $s->tail;
   }
   return $length;
} 

##############################################################################

sub insert (\@$$);

sub cutsort {
    my ( $s, $cmp, $cut, @pending ) = @_;
    my @emit;

    while ($s) {
        while ( @pending && $cut->( $pending[0], head($s) ) ) {
            push @emit, shift @pending;
        }

        if (@emit) {
            return list_to_stream( @emit,
                promise { cutsort( $s, $cmp, $cut, @pending ) } );
        }
        else {
            insert( @pending, head($s), $cmp );
            $s = tail($s);
        }
    }

    return list_to_stream( @pending, undef );
}

sub insert (\@$$) {
    my ( $a, $e, $cmp ) = @_;
    my ( $lo, $hi ) = ( 0, scalar(@$a) );
    while ( $lo < $hi ) {
        my $med = int( ( $lo + $hi ) / 2 );
        my $d = $cmp->( $a->[$med], $e );
        if ( $d <= 0 ) {
            $lo = $med + 1;
        }
        else {
            $hi = $med;
        }
    }
    splice( @$a, $lo, 0, $e );
}

=head1 EXAMPLES

Fibonacci numbers:

   use HOP::Stream qw(node promise);

   sub fibgen {
       my ($m, $n) = @_;
       return node ($m, promise { fibgen($n, $m + $n) });
   }

   $fibs = fibgen(0, 1);

Hailstone sequences:

   use HOP::Stream qw(node promise EMPTY);

   sub hailstones {
      my $n = $_[0];
      if ($n == 1) {
         return node ($n, EMPTY);
      } else {
         return node($n, promise { hailstones($n % 2 ? 3 * $n + 1 : $n / 2) });
      }
   }

   my $hailstones = hailstones(23);

Hamming's problem:

   use HOP::Stream qw(node promise transform merge);

   sub scale {
      my ($s, $c) = @_;
      return transform { $_[0] * $c } $s;
   }

   my $hamming;
   $hamming = node(1, promise { merge( scale($hamming, 2),
                                       merge( scale($hamming, 3),
                                              scale($hamming, 5) ) ) } );

=head1 AUTHOR

Mark Dominus, maintained by Curtis "Ovid" Poe, C<< <ovid@cpan.org> >> and
Brock Sides, C<< <philarete@gmail.com> >>.

=head1 BUGS

Please report any bugs or feature requests to
C<bug-hop-stream@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=HOP-Stream>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

Many thanks to Mark Dominus and Elsevier, Inc. for allowing this work to be
republished.

=head1 COPYRIGHT & LICENSE

Code derived from the book "Higher-Order Perl" by Mark Dominus, published by
Morgan Kaufmann Publishers, Copyright 2005 by Elsevier Inc.

=head1 ABOUT THE SOFTWARE

All Software (code listings) presented in the book can be found on the
companion website for the book (http://perl.plover.com/hop/) and is
subject to the License agreements below.

=head1 LATEST VERSION

You can download the latest versions of these modules at
L<http://github.com/Ovid/hop/>.  Feel free to fork and make changes.

=head1 ELSEVIER SOFTWARE LICENSE AGREEMENT

Please read the following agreement carefully before using this Software. This
Software is licensed under the terms contained in this Software license
agreement ("agreement"). By using this Software product, you, an individual,
or entity including employees, agents and representatives ("you" or "your"),
acknowledge that you have read this agreement, that you understand it, and
that you agree to be bound by the terms and conditions of this agreement.
Elsevier inc. ("Elsevier") expressly does not agree to license this Software
product to you unless you assent to this agreement. If you do not agree with
any of the following terms, do not use the Software.

=head1 LIMITED WARRANTY AND LIMITATION OF LIABILITY

YOUR USE OF THIS SOFTWARE IS AT YOUR OWN RISK. NEITHER ELSEVIER NOR ITS
LICENSORS REPRESENT OR WARRANT THAT THE SOFTWARE PRODUCT WILL MEET YOUR
REQUIREMENTS OR THAT ITS OPERATION WILL BE UNINTERRUPTED OR ERROR-FREE. WE
EXCLUDE AND EXPRESSLY DISCLAIM ALL EXPRESS AND IMPLIED WARRANTIES NOT STATED
HEREIN, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE. IN ADDITION, NEITHER ELSEVIER NOR ITS LICENSORS MAKE ANY
REPRESENTATIONS OR WARRANTIES, EITHER EXPRESS OR IMPLIED, REGARDING THE
PERFORMANCE OF YOUR NETWORK OR COMPUTER SYSTEM WHEN USED IN CONJUNCTION WITH
THE SOFTWARE PRODUCT. WE SHALL NOT BE LIABLE FOR ANY DAMAGE OR LOSS OF ANY
KIND ARISING OUT OF OR RESULTING FROM YOUR POSSESSION OR USE OF THE SOFTWARE
PRODUCT CAUSED BY ERRORS OR OMISSIONS, DATA LOSS OR CORRUPTION, ERRORS OR
OMISSIONS IN THE PROPRIETARY MATERIAL, REGARDLESS OF WHETHER SUCH LIABILITY IS
BASED IN TORT, CONTRACT OR OTHERWISE AND INCLUDING, BUT NOT LIMITED TO,
ACTUAL, SPECIAL, INDIRECT, INCIDENTAL OR CONSEQUENTIAL DAMAGES. IF THE
FOREGOING LIMITATION IS HELD TO BE UNENFORCEABLE, OUR MAXIMUM LIABILITY TO YOU
SHALL NOT EXCEED THE AMOUNT OF THE PURCHASE PRICE PAID BY YOU FOR THE SOFTWARE
PRODUCT. THE REMEDIES AVAILABLE TO YOU AGAINST US AND THE LICENSORS OF
MATERIALS INCLUDED IN THE SOFTWARE PRODUCT ARE EXCLUSIVE.

YOU UNDERSTAND THAT ELSEVIER, ITS AFFILIATES, LICENSORS, SUPPLIERS AND AGENTS,
MAKE NO WARRANTIES, EXPRESSED OR IMPLIED, WITH RESPECT TO THE SOFTWARE
PRODUCT, INCLUDING, WITHOUT LIMITATION THE PROPRIETARY MATERIAL, AND
SPECIFICALLY DISCLAIM ANY WARRANTY OF MERCHANTABILITY OR FITNESS FOR A
PARTICULAR PURPOSE.

IN NO EVENT WILL ELSEVIER, ITS AFFILIATES, LICENSORS, SUPPLIERS OR AGENTS, BE
LIABLE TO YOU FOR ANY DAMAGES, INCLUDING, WITHOUT LIMITATION, ANY LOST
PROFITS, LOST SAVINGS OR OTHER INCIDENTAL OR CONSEQUENTIAL DAMAGES, ARISING
OUT OF YOUR USE OR INABILITY TO USE THE SOFTWARE PRODUCT REGARDLESS OF WHETHER
SUCH DAMAGES ARE FORESEEABLE OR WHETHER SUCH DAMAGES ARE DEEMED TO RESULT FROM
THE FAILURE OR INADEQUACY OF ANY EXCLUSIVE OR OTHER REMEDY.

=head1 SOFTWARE LICENSE AGREEMENT

This Software License Agreement is a legal agreement between the Author and
any person or legal entity using or accepting any Software governed by this
Agreement. The Software is available on the companion website
(http://perl.plover.com/hop/) for the Book, Higher-Order Perl, which is
published by Morgan Kaufmann Publishers. "The Software" is comprised of all
code (fragments and pseudocode) presented in the book.

By installing, copying, or otherwise using the Software, you agree to be bound
by the terms of this Agreement.

The parties agree as follows:

=over 4

=item 1 Grant of License

We grant you a nonexclusive license to use the Software for any purpose,
commercial or non-commercial, as long as the following credit is included
identifying the original source of the Software: "from Higher-Order Perl by
Mark Dominus, published by Morgan Kaufmann Publishers, Copyright 2005 by
Elsevier Inc".

=item 2 Disclaimer of Warranty. 

We make no warranties at all. The Software is transferred to you on an "as is"
basis. You use the Software at your own peril. You assume all risk of loss for
all claims or controversies, now existing or hereafter, arising out of use of
the Software. We shall have no liability based on a claim that your use or
combination of the Software with products or data not supplied by us infringes
any patent, copyright, or proprietary right. All other warranties, expressed
or implied, including, without limitation, any warranty of merchantability or
fitness for a particular purpose are hereby excluded.

=item 3 Limitation of Liability. 

We will have no liability for special, incidental, or consequential damages
even if advised of the possibility of such damages. We will not be liable for
any other damages or loss in any way connected with the Software.

=back

=cut

1;    # End of HOP::Stream
