#!/usr/bin/perl
use warnings;
use strict;

use Test::More tests => 114; 
#use Test::More 'no_plan';

use lib 'lib/', '../lib/';

BEGIN {
    use_ok 'HOP::Stream', ':all' or die;
}

my @exported = qw(
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
  genstream
);

foreach my $function (@exported) {
    no strict 'refs';
    ok defined &$function, "&$function should be exported to our namespace";
}

# node

ok my $stream = node( 3, 4 ), 'Calling node() should succeed';
is_deeply $stream, [ 3, 4 ], '... returning a stream node';
ok my $new_stream = node( 7, $stream ),
  '... and a node may be in the node() arguments';
is_deeply $new_stream, [ 7, $stream ], '... and the new node should be correct';

# head
is head($new_stream), 7, 'head() should return the head of a node';

# tail

is tail($new_stream), $stream, 'tail() should return the tail of a node';

# storing errors encountered when running tail
my $badstream = node(1, promise { die "Ack!" });
$badstream = $badstream->tail;
ok HOP::Stream::is_error($badstream->[0]), 'tail() should store any error thrown when it fulfills a promise';
eval { $badstream->head };
ok $@ =~ m/^Ack!/, 'head() should die with that error';

# EMPTY
ok ((not defined EMPTY), 'EMPTY should return undef');

# is_empty
ok is_empty(undef), 'is_empty should return true if its argument is undefined';
ok ((not is_empty(1)), '... and false otherwise');

# pick
my $pickstream = node(0, node(1, node(2, (node 3, undef))));
ok $pickstream->pick(2) == 2, 'pick() should pick the correct element';
ok ((not defined pick(EMPTY, 0)), '... and should return undef if called on EMPTY');

# take
my $takefrom = node(0, node(1, node(2, (node 3, undef))));
my $taken = $takefrom->take(2);
ok ref($taken) eq 'HOP::Stream', 'take() should return a stream';
ok $taken->head == 0, '... with the first element 0';
ok $taken->tail->head == 1, '... with the second element 1';
ok is_empty(take(EMPTY, 10)), '... and should return EMPTY when called on EMPTY';

# discard
my $discardfrom = list2stream(1 .. 20);
my $discarded = $discardfrom->discard(10);
ok ref($discarded) eq 'HOP::Stream', 'discard() should return a stream';
my @discarded = $discarded->stream2list;
is_deeply \@discarded, [11 .. 20], '... and should discard the first n elements from its input stream';
$discarded = discard(EMPTY, 10);
ok is_empty($discarded), '... and should return EMPTY when called on EMPTY';

# drop

ok my $head = drop($new_stream), 'drop() should succeed';
is $head, 7, '... returning the head of the node';
is_deeply $new_stream, $stream,
  '... and setting the tail of the node as the node';

# upto

ok !upto( 5, 4 ),
  'upto() should return false if the first number is greater than the second';
ok $stream = upto( 4, 7 ),
  '... but it should succeed if the first number is less than the second';

my @numbers;
while ( defined( my $num = drop($stream) ) ) {
    push @numbers, $num;
}
is_deeply \@numbers, [ 4, 5, 6, 7 ],
  '... and the stream should return all of the numbers';

# upfrom
ok $stream = upfrom(42), 'upfrom() should return a stream';

@numbers = ();
for ( 1 .. 10 ) {
    push @numbers, drop($stream);
}
is_deeply \@numbers, [ 42 .. 51 ],
  '... which should return the numbers we expect';

# show

show( $stream, 5 );
is show( $stream, 5 ), "52 53 54 55 56 ", 'Show should print the correct values';

# transform

my $evens = transform { $_[0] * 2 } upfrom(1);
ok $evens, 'Calling transform() on a stream should succeed';

@numbers = ();
for ( 1 .. 5 ) {
    push @numbers, drop($evens);
}
is_deeply \@numbers, [ 2, 4, 6, 8, 10 ],
  '... which should return the numbers we expect';

ok is_empty( transform { 0 } EMPTY ), '... and should return EMPTY when called on EMPTY';

# filter

# forget the parens in the filter and it's an infinite loop
$evens = filter { !( $_[0] % 2 ) } upfrom(1);
ok $evens, 'Calling filter() on a stream should succeed';

@numbers = ();
for ( 1 .. 5 ) {
    push @numbers, drop($evens);
}
is_deeply \@numbers, [ 2, 4, 6, 8, 10 ],
  '... and should return the numbers we expect';

ok is_empty( filter { $_[0] } EMPTY ), '... and should return EMPTY when called on EMPTY';

# append

my $stream1 = upto(4, 7);
my $stream2 = upto(12, 15);
my $stream3 = upto(25, 28);
ok $stream = append($stream1, $stream2, $stream3),
  "append() should return a stream";

@numbers = ();
while ( defined( my $num = drop($stream) ) ) {
    push @numbers, $num;
}
is_deeply \@numbers, [ 4..7, 12..15, 25..28 ],
  '... and the stream should return all of the numbers';

# list2stream

ok $stream = list2stream( 1 .. 10 ),
  'list2stream() should return a stream';
@numbers = ();
while ( defined( my $num = drop($stream) ) ) {
    push @numbers, $num;
}
is_deeply \@numbers, [ 1 .. 10 ], '... and create the numbers one to ten';

# stream2list

$stream = node(1, node(2, node(3, node(4, node(5, undef)))));
my @list = stream2list($stream);
is_deeply \@list, [ 1 .. 5 ], 'stream2list should return one to five';

# fuse

my $odds = list2stream(1, 3, 5, 7, 9);
$evens = list2stream(2, 4, 6, 8, 10);
my $fused = fuse($odds, $evens);
my @fused = stream2list($fused);
is_deeply \@fused, [ 1 .. 10 ], 'fuse() should merge sorted streams';

my $s1 = list2stream(1, 2, 3);
my $s2 = list2stream(1, 2, 3);
$fused = fuse($s1, $s2);
@fused = stream2list($fused);
is_deeply \@fused, [ 1, 1, 2, 2, 3, 3 ], '... without deleting duplicate elements';

$odds = list2stream(9, 7, 5, 3, 1);
$evens = list2stream(10, 8, 6, 4, 2);
$fused = fuse($odds, $evens, sub { $_[0] > $_[1] });
@fused = stream2list($fused);
is_deeply \@fused, [ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 ], '... and should merge using an alternate comparison operator';

ok $odds eq fuse($odds, EMPTY), '... and handles EMPTY in the right-had place';
ok $evens eq fuse(EMPTY, $evens), '... and the left-had place';
ok is_empty(fuse(EMPTY, EMPTY)), '... and in both places';


# uniq

$stream = list2stream(1, 1, 2, 2, 3, 3, 4, 4, 5, 5);
my @uniq = $stream->uniq->stream2list;
is_deeply \@uniq, [1, 2, 3, 4, 5], 'uniq() should remove duplicates from a stream';
$stream = list2stream qw(a a b b c c d d e e);
@uniq = $stream->uniq( sub {$_[0] eq $_[1]} )->stream2list;
is_deeply \@uniq, ['a', 'b', 'c', 'd', 'e'], '... using an alternative equality operator';
ok is_empty(uniq(EMPTY)), '... and should return EMPTY when given EMPTY.';


# merge

sub scale {
    my ( $s, $c ) = @_;
    transform { $_[0] * $c } $s;
}

my $hamming;
$hamming = node(
    1,
    promise {
        merge(
            scale( $hamming, 2 ),
            merge( scale( $hamming, 3 ), scale( $hamming, 5 ), )
        )
    }
);

@numbers = ();
for ( 1 .. 10 ) {
    push @numbers, drop($hamming);
}
is_deeply \@numbers, [ 1, 2, 3, 4, 5, 6, 8, 9, 10, 12 ],
  'merge() should let us merge sorted streams';

$evens = transform { $_[0] * 2 } upfrom(1);
$odds = transform { ( $_[0] * 2 ) - 1 } upfrom(1);
my $number = merge( $odds, $evens );

@numbers = ();
for ( 1 .. 10 ) {
    push @numbers, drop($number);
}
is_deeply \@numbers, [ 1 .. 10 ], '... and create the numbers one to ten';

# iterator_to_stream

my @iter = qw/2 4 6 8/;
my $iter = sub { shift @iter };
ok $stream = iterator_to_stream($iter),
  'iterator_to_stream() should convert an iterator to a stream';
@numbers = ();
while ( defined( my $number = drop($stream) ) ) {
    push @numbers, $number;
}
is_deeply \@numbers, [ 2, 4, 6, 8 ],
  '... and the stream should return the correct values';

# stream_to_iterator

$stream = node(0, node(1, node(2, undef)));
$iter = stream_to_iterator($stream);
ok ref($iter) eq 'CODE', 'stream_to_iterator() should return an iterator';
ok $iter->() == 0, '... which should return 0';
ok $iter->() == 1, '... and then 1';
ok $iter->() == 2, '... and then 2';

# list_to_stream

ok my $list = list_to_stream( 1 .. 9, node(10) ),
  'list_to_stream() should return a stream';
@numbers = ();
while ( defined( my $num = drop($list) ) ) {
    push @numbers, $num;
}
is_deeply \@numbers, [ 1 .. 10 ], '... and create the numbers one to ten';

# list_to_stream, final node computed internally

ok $stream = list_to_stream( 1 .. 10 ),
  'list_to_stream() should return a stream';
@numbers = ();
while ( defined( my $num = drop($stream) ) ) {
    push @numbers, $num;
}
is_deeply \@numbers, [ 1 .. 10 ], '... and create the numbers one to ten';

# insert

@list = qw/seventeen three one/;                # sorted by descending length
my $compare = sub { length $_[0] < length $_[1] };
insert @list, 'four', $compare;
is_deeply \@list, [qw/seventeen three four one/],
  'insert() should be able to insert items according to our sort criteria';

# constants

my $zeroes = constants(0);
ok ref($zeroes) eq 'HOP::Stream', 'constants() should return a stream';
my @zeroes = $zeroes->take(10)->stream2list;
is_deeply \@zeroes, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], '... of one element repeated';
my $onetwothree = constants(1, 2, 3);
my @onetwothree = $onetwothree->take(10)->stream2list;
is_deeply \@onetwothree, [1, 2, 3, 1, 2, 3, 1, 2, 3, 1], '... or several repeated';

# fold

my $s = list2stream(1 .. 100);
my $sum = $s->fold(sub { $_[0] + $_[1] }, 0);
ok $sum == 5050, 'fold() should be able to sum a stream';
ok fold(EMPTY, sub { }, 42) == 42, '... and should return its base if called on EMPTY';

# genstream
my $s = genstream { $_[0] + 1 } 0;
ok ref($s) eq 'HOP::Stream', 'genstream() should return a stream';
my @ints = $s->take(10)->stream2list;
is_deeply \@ints, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], '... and should generate an appropriate stream';


# 
# streams of array refs do not work properly, because tail [a,b] is b, even if [a,b] is
# the last stream element, and not a node
# Solution: bless nodes, check is_node in head, tail, list_to_stream
#
$stream = list_to_stream( [A => 1], [B => 2] );
$stream->tail; # fulfill the promise in the tail
is_deeply $stream, 
  bless([ [A => 1], 
          bless([ [B => 2], 
                  undef ],
              'HOP::Stream')],
      'HOP::Stream'), "stream of array refs";
is_deeply head($stream), [A => 1], "... head is array ref";
is_deeply tail($stream), 
  bless([ [B => 2], 
          undef ],
      'HOP::Stream'), "... tail is stream";

drop($stream);
is_deeply $stream, 
  bless([ [B => 2], 
          undef ],
      'HOP::Stream'), "stream of array refs, dropped 1";
is_deeply head($stream), [B => 2], "... head is array ref";
is_deeply tail($stream), undef, "... tail is stream";

drop($stream);
is_deeply $stream, undef, "stream of array refs, dropped 2";
is_deeply head($stream), undef, "... head is undef";
is_deeply tail($stream), undef, "... tail is undef";

drop($stream);
is_deeply $stream, undef, "stream of array refs, dropped 3";
is_deeply head($stream), undef, "... head is undef";
is_deeply tail($stream), undef, "... tail is undef";

# 
# use a non-stream as stream
#
$stream = [1, [2, [3]]];
is head($stream), undef, "no head of non-stream";
is tail($stream), undef, "no head of non-stream";
