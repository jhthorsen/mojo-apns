# use IO::Socket::SSL qw(debug3);
use warnings;
use strict;
use Mojo::APNS;
use Test::More;
use File::Basename;
use Mojo::IOLoop::Stream;

my $dir = dirname $INC{'Mojo/IOLoop/Stream.pm'};
my $port = Mojo::IOLoop->generate_port;
my $message;

plan skip_all => 'Could not find Mojo cert' unless -e "$dir/server.crt";
plan skip_all => 'Could not find Mojo key' unless -e "$dir/server.key";

Mojo::IOLoop->server(
  port => $port,
  address => '127.0.0.1',
  tls => 1,
  tls_cert => "$dir/server.crt",
  tls_key => "$dir/server.key",
  sub {
    my($loop, $stream, $id) = @_;
    $stream->on(read => sub {
      $message = $_[1];
      Mojo::IOLoop->stop;
    });
  },
);

my $apns = Mojo::APNS->new(
            key => "$dir/server.key",
            cert => "$dir/server.crt",
            sandbox => 1,
            _gateway_address => '127.0.0.1',
            _gateway_port => $port,
           );

$apns->on(error => sub { diag "ERROR: $_[1]"; $_[0]->ioloop->stop; });

$apns->send(
  "c9d4a07c fbbc21d6 ef87a47d 53e16983 1096a5d5 faa15b75 56f59ddd a715dff4",
  "New cool stuff!",
  badge => 2,
);

$apns->ioloop->start;

diag length $message;
is substr($message, 0, 1), chr(0), 'message starts with null chr';
is unpack('n', substr $message, 1, 2), '32', 'pack n 32';
is unpack('H*', substr $message, 3, 32), 'c9d4a07cfbbc21d6ef87a47d53e169831096a5d5faa15b7556f59ddda715dff4', 'device id';
is unpack('n', substr $message, -47, 2), 45, 'message length';
is_deeply(
    $apns->_json->decode(substr($message, -45)),
    {
      aps => {
        alert => 'New cool stuff!',
        badge => 2,
      },
    },
    'message'
);

done_testing;
