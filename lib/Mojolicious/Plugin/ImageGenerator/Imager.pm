package Mojolicious::Plugin::ImageGenerator::Imager;

use strict;
use warnings;

use base 'Mojo::Base';

use Imager;

__PACKAGE__->attr(image => sub { Imager->new });

sub load {
    my $self = shift;
    my ($path) = @_;

    return $self->image->read(file => $path);
}

sub width { shift->image->getwidth }
sub height { shift->image->getheight }

sub apply_filter {
    my $self = shift;
    my ($name, @args) = @_;

    if ($name eq 'grayscale') {
        my $image = $self->image->convert(preset => 'gray');
        $self->image($image);
    }
}

sub scale {
    my $self = shift;
    my %params = @_;

    my $image = $self->image->scale(
        xpixels => $params{width},
        ypixels => $params{height}
    );
    return unless $image;

    $self->image($image);
    return 1;
}

sub crop {
    my $self = shift;
    my %params = @_;

    my $image = $self->image->crop(
        left   => $params{left},
        width  => $params{width},
        top    => $params{top},
        height => $params{height}
    );
    return unless $image;

    $self->image($image);
    return 1;
}

sub save {
    my $self = shift;
    my ($path) = @_;

    return $self->image->write(file => $path);
}

1;
