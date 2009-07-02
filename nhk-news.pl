#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use URI;
use LWP::UserAgent;
use HTML::TokeParser;
use HTML::ExtractContent;
use XML::Feed;
use Gtk2 -init;
use Gtk2::SimpleList;
use Gtk2::Ex::MPlayerEmbed;

### Window
my $window = Gtk2::Window->new('toplevel');
$window->set_title('NHK News');
$window->set_icon_name('gnome-multimedia');
$window->set_default_size( 500, 500 );

my $tooltips = Gtk2::Tooltips->new;

### VBox
my $vbox = Gtk2::VBox->new;
$window->add($vbox);

my ( $player, $feeds, $entries );

### Feeds
$feeds =
Gtk2::ComboBox->new_with_model(
	Gtk2::ListStore->new( 'Glib::String', 'Glib::String', ) );
my $renderer = Gtk2::CellRendererText->new;
$feeds->pack_start( $renderer, 1 );
$feeds->add_attribute( $renderer, text => 0 );
$feeds->signal_connect(
	changed => sub {
		my ($cb) = @_;
		my $url   = $cb->get_model->get( $cb->get_active_iter, 1 );
		my $feed  = XML::Feed->parse( URI->new($url) );
		my $model = $entries->get_model;
		$model->clear;
		for my $item ( $feed->entries ) {
			$model->set( $model->append, 0 => $item->title, 1 => $item->link );
		}
	}
);
$vbox->pack_start( $feeds, 0, 0, 0 );

### Entries
$entries = Gtk2::SimpleList->new(
	'ニュース一覧' => 'text',
	'URL'                => 'text'
);
$entries->signal_connect(
	row_activated => sub {
		my ( $sl, $path, $column ) = @_;
		my $row_ref = $sl->get_row_data_from_path($path);
		my $content =
		LWP::UserAgent->new->get( URI->new( @$row_ref[1] ) )->decoded_content;
		my $extractor = HTML::ExtractContent->new;
		$extractor->extract($content);
		$tooltips->set_tip( $player, $extractor->as_text );
		if ( $content =~ m|wmvHigh = "(.*?)";|s ) {
			if ( $player->get('loaded') && $player->get('state') ne 'stopped' )
			{
				$player->stop if $player->get('state') eq 'playing';
			}
			$player->play($1);
		}
	}
);

### Wrapped scrolled window for entries.
my $scrolledwindow = Gtk2::ScrolledWindow->new( undef, undef );
$scrolledwindow->add($entries);
$scrolledwindow->set_size_request( -1, 150 );
$vbox->pack_start( $scrolledwindow, 0, 0, 0 );

### Player
$player = Gtk2::Ex::MPlayerEmbed->new;
$player->{args} = '-playlist';
$window->signal_connect(
	destroy => sub {
		if ( $player->get('loaded') && $player->get('state') ne 'stopped' ) {
			$player->stop if $player->get('state') eq 'playing';
		}
		Gtk2->main_quit;
		exit;
	}
);
$vbox->add($player);

$window->show_all;
make_feeds( $feeds->get_model );
Gtk2->main;

exit;

sub make_feeds {
	my $model  = shift;

	my $res    = LWP::UserAgent->new->get( URI->new('http://www.nhk.or.jp/') );
	my $parser = HTML::TokeParser->new( \$res->decoded_content );
	while ( my $token = $parser->get_tag("link") ) {
		my $attr = $token->[1];
		if (
			$attr->{rel} eq 'alternate'
			&& (   $attr->{type} eq 'application/rss+xml'
					or $attr->{type} eq 'application/atom+xml' )
		)
		{
			$model->set(
				$model->append,
				0 => $attr->{title},
				1 => $attr->{href}
			);
		}
	}
}
