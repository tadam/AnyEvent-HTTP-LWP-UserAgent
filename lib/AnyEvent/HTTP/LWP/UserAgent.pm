package AnyEvent::HTTP::LWP::UserAgent;

use strict;
use warnings;

#ABSTRACT: LWP::UserAgent interface but works using AnyEvent::HTTP

=head1 SYNOPSIS

  use AnyEvent::HTTP::LWP::UserAgent;
  use Coro;

  my $ua = AnyEvent::HTTP::LWP::UserAgent->new;
  my @urls = (...);
  my @coro = map {
      async {
          my $url = $_;
          my $r = $ua->get($url);
          print "url $url, content " . $r->content . "\n";
      }
  } @urls;
  $_->join for @coro;

=head1 DESCRIPTION

When you use Coro you have a choice: you can use L<Coro::LWP> or L<AnyEvent::HTTP>
(if you want to make asynchronous HTTP requests).
If you use Coro::LWP, some modules may work incorrectly (for example Cache::Memcached)
because of global change of IO::Socket behavior.
AnyEvent::HTTP uses different programming interface, so you must change more of your
old code with LWP::UserAgent (and HTTP::Request and so on), if you want to make
asynchronous code.

AnyEvent::HTTP::LWP::UserAgent uses AnyEvent::HTTP inside but have an interface of
LWP::UserAgent.
You can safely use this module in Coro environment (and possibly in AnyEvent too).

=head1 LIMITATIONS AND DETAILS

You can use it only for HTTP(S)/1.0 requests.

Some features of LWP::UserAgent can be broken (C<protocols_forbidden>, C<conn_cache>
or something else). Precise documentation and realization of these features will come
in the future.

You can use some AnyEvent::HTTP global function and variables.
But use C<agent> of UA instead of $AnyEvent::HTTP::USERAGENT and C<max_redirect> instead of
$AnyEvent::HTTP::MAX_RECURSE

=head1 SEE ALSO

L<http://github.com/tadam/AnyEvent-HTTP-LWP-UserAgent>, L<Coro::LWP>, L<AnyEvent::HTTP>

=cut

use parent qw(LWP::UserAgent);

use AnyEvent::HTTP;
use HTTP::Response;

sub simple_request {
    my ($self, $in_req, $arg, $size) = @_;

    my ($method, $uri, $args) = $self->lwp_request2anyevent_request($in_req);

    my $cv = AE::cv;
    $cv->begin;
    my $out_req;
    http_request $method => $uri, %$args, sub {
        my ($d, $h) = @_;
        my $code = delete $h->{Status};
        my $message = delete $h->{Reason};
        my @headers;
        while (my @h = each %$h) {
            push @headers, @h;
        }
        if ($code >= 590 && $code <= 599) {
            if ($message =~ /timed/ && $code == 599) {
                $d = '500 read timeout';
                $code = 500;
            } elsif (!defined($d) || $d =~ /^\s*$/) {
                $d = $message;
            }
        }
        $out_req = HTTP::Response->new($code, $message, \@headers, $d);
        $cv->end;
    };
    $cv->recv;

    $out_req->request($in_req);

    return $out_req;
}

sub lwp_request2anyevent_request {
    my ($self, $in_req) = @_;

    my $method = $in_req->method;
    my $uri = $in_req->uri->as_string;

    my $in_headers = $in_req->headers;
    my $out_headers = {};
    $in_headers->scan( sub {
        my ($header, $value) = @_;
        $out_headers->{$header} = $value;
    } );
    $out_headers->{'User-Agent'} = $self->agent;

    my $body = $in_req->content;

    my %args = (
        headers => $out_headers,
        body    => $body,
        recurse => 0,
        timeout => $self->timeout,
    );
    return ($method, $uri, \%args);
}

1;
