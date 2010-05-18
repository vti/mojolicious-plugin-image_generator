package Mojolicious::Plugin::ImageGenerator;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::ByteStream;
require File::Path;
require File::Spec;

use constant IMAGER =>
  eval { require Mojolicious::Plugin::ImageGenerator::Imager; 1 };

sub register {
    my ($self, $app, $conf) = @_;

    # Plugin config
    $conf ||= {};

    # Default sizes
    $conf->{sizes} ||= {
        small  => {size => '200x200', filters => 'grayscale'},
        normal => '160x160'
    };

    $conf->{srcdir} ||= 'images';
    $conf->{dstdir} ||= 'images';

    $conf->{srcdir} =~ s{^/}{};
    $conf->{dstdir} =~ s{^/}{};

    my $srcdir = $app->home->rel_dir($conf->{srcdir});
    my $dstdir = File::Spec->catfile($app->static->root, $conf->{dstdir});

    $self->_create_dir($app, $srcdir) unless -d $srcdir;
    $self->_create_dir($app, $dstdir) unless -d $dstdir;

    my $prefix = $conf->{prefix};

    $app->log->debug(qq/Source directory $srcdir/);
    $app->log->debug(qq/Destination directory $dstdir/);

    # Add hook
    $app->plugins->add_hook(
        before_dispatch => sub {
            my ($self, $c) = @_;

            my $path = $c->req->url->path;
            if ($path && $path =~ m|^/$conf->{dstdir}/(.*?)/(.*)|) {
                my $size = $1;
                my $fullpath = $2;

                # Unknown size
                return unless $conf->{sizes}->{$size};

                # Unescape path (%20 -> ' ')

                # Already there (will be served by static dispatcher)
                my $dstpath = File::Spec->catfile($dstdir, $size, $fullpath);
                return if -r $dstpath;

                # Source image not found (404 will be served by static dispatcher)
                my $srcpath = File::Spec->catfile($srcdir, $fullpath);
                return unless -r $srcpath;

                # Attempt resizing
                my $ok =
                  _resize($app, $conf->{sizes}->{$size}, $srcpath, $dstpath);

                # Failed on resize (hack to stop workflow)
                unless ($ok) {
                    $c->render_exception(qq/Can't resize an image/);
                    die qq/Can't resize an image/;
                    return;
                }

                # Static file (will be served by static dispatcher)
                return;
            }
        }
    );

    return;
}

sub _create_dir {
    my ($self, $app, $dir) = @_;

    $app->log->debug(qq/Creating $dir/);
    File::Path::mkpath($dir) or die qq/Can't make directory "$dir": $!/;
}

sub _resize {
    my ($app, $params, $from, $to) = @_;

    my ($geometry, $filters);

    if (ref($params) eq 'HASH') {
        $geometry = $params->{size};
        $filters = $params->{filters};
    }
    else {
        $geometry = $params;
    }

    my $image = _get_image();
    $app->log->debug(qq/Can't find a suitable image class/), return
      unless $image;

    $app->log->debug(qq/Can't load image/), return
      unless $image->load($from);

    my ($from_width, $from_height) = ($image->width, $image->height);
    $app->log->debug(qq/Can't get image geometry/), return
      unless $from_width && $from_height;

    my ($to_width, $to_height) = split('x', $geometry);

    # Box
    if ($to_width && $to_height) {
        $app->log->debug(qq/Can't scale an image/), return
          unless $image->scale(width => $to_width, height => $to_height);

        $app->log->debug(qq/Can't crop an image/), return
          unless $image->crop(
            left   => ($image->width - $to_width) / 2,
            width  => $to_width,
            top    => ($image->width - $to_height) / 2,
            height => $to_height
          );
    }

    # Max width
    elsif ($to_width) {
        return unless $image->scale(width => $to_width);
    }

    # Max height
    else {
        return unless $image->scale(height => $to_height);
    }

    if ($filters) {
        $filters = [$filters] unless ref($filters) eq 'ARRAY';
        foreach my $filter (@$filters) {
            $image->apply_filter($filter);
        }
    }

    my $to_dir = File::Basename::dirname($to);
    File::Path::mkpath($to_dir) unless -d $to_dir;

    $app->log->debug(qq/Can't save an image/), return
      unless $image->save($to);

    return 1;
}

sub _get_image {
    my $class;

    if (IMAGER) {
        $class = 'Imager';
    }
    else {
        return;
    }

    $class = "Mojolicious::Plugin::ImageGenerator::$class";

    return $class->new;
}

1;
