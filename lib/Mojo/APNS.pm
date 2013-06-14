package Mojo::APNS;

=head1 NAME

Mojo::APNS - Apple Push Notification Service for Mojolicious

=head1 VERSION

0.03

=head1 DESCRIPTION

This module provides an API for sending messages to an iPhone using Apple Push
Notification Service.

This module does not support password protected SSL keys.

=head1 SYNOPSIS

  use Mojo::APNS;

  my $apns = Mojo::APNS->new(
              key => '/path/to/apns-dev-key.pem',
              cert => '/path/to/apns-dev-cert.pem',
              sandbox => 1,
            );

  $apns->on(drain => sub { $apns->loop->stop; })
  $apns->send(
    "c9d4a07c fbbc21d6 ef87a47d 53e16983 1096a5d5 faa15b75 56f59ddd a715dff4",
    "New cool stuff!",
    badge => 2,
  );

  $apns->on(feedback => sub {
    my($apns, $feedback) = @_;
    warn "$feedback->{device} rejected push at $feedback->{ts}";
  });

  $apns->ioloop->start;

=cut

use feature 'state';
use Mojo::Base 'Mojo::EventEmitter';
use Mojo::JSON;
use Mojo::IOLoop;
use constant FEEDBACK_RECONNECT_TIMEOUT => 5;
use constant DEBUG => $ENV{MOJO_APNS_DEBUG} ? 1 : 0;

our $VERSION = '0.03';

=head1 EVENTS

=head2 error

Emitted when an error occur between client and server.

=head2 drain

Emitted once all messages have been sent to the server.

=head2 feedback

  $self->on(feedback => sub {
    my($self, $data) = @_;
    # ...
  });

This event is emitted once a device has rejected a notification. C<$data> is a
hash-ref:

  {
    ts => $rejected_epoch_timestamp,
    device => $device_token,
  }

Once you start listening to "feedback" events, a connection will be made to
Apple's push notification server which will then send data to this callback.

=head1 ATTRIBUTES

=head2 cert

Path to apple SSL certificate.

=head2 key

Path to apple SSL key.

=head2 sandbox

Booleand true for talking with "gateway.sandbox.push.apple.com". Default is to
use "gateway.push.apple.com"

=head2 ioloop

Holds a L<Mojo::IOLoop> object.

=cut

has key => '';
has cert => '';
has sandbox => 0;

has ioloop => sub { Mojo::IOLoop->singleton };
has _feedback_port => 2196;
has _gateway_port => 2195;
has _gateway_address => sub {
  $_[0]->sandbox ? 'gateway.sandbox.push.apple.com' : 'gateway.push.apple.com'
};

sub _json { state $json = Mojo::JSON->new }

=head1 METHODS

=head2 on

Same as L<Mojo::EventEmitter/on>, but will also set up feedback connection if
the event is L</feedback>.

=cut

sub on {
  my($self, $event, @args) = @_;

  if($event eq 'feedback' and !$self->{feedback_id}) {
    $self->_connect(feedback => $self->_connected_to_feedback_deamon_cb);
  }

  $self->SUPER::on($event => @args);
}

sub _connected_to_feedback_deamon_cb {
  my $self = shift;
  my($bytes, $ts, $device) = ('');

  sub {
    my($self, $stream) = @_;
    Scalar::Util::weaken($self);
    $stream->timeout(0);
    $stream->on(close => sub {
      $stream->reactor->timer(FEEDBACK_RECONNECT_TIMEOUT, sub {
        $self or return;
        $self->_connect(feedback => $self->_connected_to_feedback_deamon_cb);
      });
    });
    $stream->on(read => sub {
      $bytes .= $_[1];
      ($ts, $device, $bytes) = unpack 'N n/a a*', $bytes;
      warn "[APNS:$device] >>> $ts\n" if DEBUG;
      $self->emit(feedback => { ts => $ts, device => $device });
    });
  };
}

=head2 send

  $self->send($device, $message, %args);
  $self->send($device, $message, %args, $cb);

Will send a C<$message> to the C<$device>. C<%args> is optional, but can contain:

C<$cb> will be called when the messsage has been sent or if it could not be
sent. C<$error> will be false on success.

    $cb->($self, $error);

=over 4

=item * badge

The number placed on the app icon. Default is 0.

=item * sound

Default is "default".

=item * Custom arguments

=back

=cut

sub send {
  my $cb = ref $_[-1] eq 'CODE' ? pop : \&_default_handler;
  my($self, $device_token, $message, %args) = @_;
  my $data = {};

  $data->{aps} = {
    alert => $message,
    badge => int(delete $args{badge} || 0),
  };

  if(length(my $sound = delete $args{sound})) {
    $data->{aps}{sound} = $sound;
  }
  if(%args) {
    $data->{custom} = \%args;
  }

  $message = $self->_json->encode($data);

  if(length $message > 256) {
    my $length = length $message;
    return $self->$cb("Too long message ($length)");
  }

  $device_token =~ s/\s//g;
  warn "[APNS:$device_token] <<< $message\n" if DEBUG;

  $self->once(drain => sub { $self->$cb('') });
  $self->_write([
    chr(0),
    pack('n', 32),
    pack('H*', $device_token),
    pack('n', length $message),
    $message,
  ]);
}

sub _connect {
  my($self, $type, $cb) = @_;
  my $port = $type eq 'gateway' ? $self->_gateway_port : $self->_feedback_port;
  my @cleanup = map { "${type}_$_" } qw/ id stream /;

  if(DEBUG) {
    my $key = join ':', $self->_gateway_address, $port;
    warn "[APNS:$key] <<< cert=@{[$self->cert]}\n" if DEBUG;
    warn "[APNS:$key] <<< key=@{[$self->key]}\n" if DEBUG;
  }

  Scalar::Util::weaken($self);
  $self->{$cleanup[0]}
    ||= $self->ioloop->client(
        address => $self->_gateway_address,
        port => $port,
        tls => 1,
        tls_cert => $self->cert,
        tls_key => $self->key,
        sub {
          my($ioloop, $error, $stream) = @_;

          $error and return $self->emit(error => "$type: $error");
          $self->{$cleanup[1]} = $stream;
          $stream->on(close => sub { delete $self->{$_} for @cleanup });
          $stream->on(error => sub { $self->emit(error => "$type: $_[1]") });
          $stream->on(drain => sub { $self->emit('drain'); });
          $stream->on(timeout => sub { delete $self->{$_} for @cleanup });
          $self->$cb($stream);
        },
      );
}

sub _default_handler {
  $_[0]->emit(error => $_[1]) if $_[1];
}

sub _write {
  my($self, $message) = @_;

  if($self->{gateway_stream}) {
    $self->{gateway_stream}->write(join '', @$message);
  }
  else {
    $self->_connect(gateway => sub { shift->_write($message) }) unless $self->{gateway_id};
  }

  $self;
}

sub DESTROY {
  my $self = shift;
  my $ioloop = $self->ioloop or return;

  if(my $id = $self->{gateway_id}) {
    $ioloop->remove($id);
  }
  if(my $id = $self->{feedback_id}) {
    $ioloop->remove($id);
  }
}

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
