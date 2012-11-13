use strict;
use Test::More tests => 1;
use AnyEvent::HTTP::LWP::UserAgent;

my $ua = AnyEvent::HTTP::LWP::UserAgent->new;
my $res = $ua->get('http://example.com/');
ok ! $res->is_success;
