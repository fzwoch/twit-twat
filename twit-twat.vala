/*
 * Twit-Twat
 *
 * Copyright (C) 2017-2021 Florian Zwoch <fzwoch@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

using Gtk;
using Gdk;
using Gst;

class TwitTwatApp : Gtk.Application {
	string channel = "";
	const string client_id_priv = "7ikopbkspr7556owm9krqmalvr2w0i4";
	const string client_id = "kimne78kx3ncx6brgo4mv6wki5h1ko";
	dynamic Element playbin = null;
	Gtk.Window window = null;

	public override void activate () {
		var builder = new Builder.from_resource ("/twit-twat/twit-twat.glade");

		window = builder.get_object ("window") as ApplicationWindow;
		add_window (window);

		var sink = ElementFactory.make ("gtkglsink", null) as dynamic Element;

		window.add (sink.widget);
		window.show_all ();

		var bin = ElementFactory.make ("glsinkbin", null) as dynamic Element;
		bin.sink = sink;

		playbin = ElementFactory.make ("playbin", null);
		playbin.video_sink = bin;

		var volume = builder.get_object ("volume") as VolumeButton;
		volume.value_changed.connect ((value) => {
			playbin.volume = value;
		});

		var bitrate = builder.get_object ("bitrate") as Scale;

		bitrate.value_changed.connect ((range) => {
			playbin.connection_speed = (int) range.get_value ();
		});

		var entry = builder.get_object ("channel") as Entry;
		entry.activate.connect ((entry) => {
			channel = entry.text.strip ().down ();

			var session = new Soup.Session ();
			var message = new Soup.Message ("GET", "https://api.twitch.tv/kraken/users?login=" + channel);

			message.request_headers.append ("Client-ID", client_id_priv);
			message.request_headers.append ("Accept", "application/vnd.twitchtv.v5+json");

			session.ssl_strict = false;
			session.queue_message (message, get_access_token);

			var popover = builder.get_object ("popover_channel") as Popover;
			popover.hide ();
		});

		var fullscreen = builder.get_object ("fullscreen") as Button;
		fullscreen.clicked.connect (() => {
			window.fullscreen ();
		});

		playbin.get_bus ().add_watch (Priority.DEFAULT, (bus, message) => {
			switch (message.type) {
				case Gst.MessageType.EOS:
					playbin.set_state (State.READY);
					var dialog = new MessageDialog (window, DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.INFO, ButtonsType.CLOSE, "Broadcast finished");
					dialog.run ();
					dialog.destroy ();
					break;
				case Gst.MessageType.WARNING:
					Error err;
					message.parse_warning (out err, null);
					warning (err.message);
					break;
				case Gst.MessageType.ERROR:
					Error err;
					playbin.set_state (State.READY);
					message.parse_error (out err, null);
					var dialog = new MessageDialog (window, DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, ButtonsType.CLOSE, err.message);
					dialog.run ();
					dialog.destroy ();
					break;
				case Gst.MessageType.BUFFERING:
					int percent = 0;
					message.parse_buffering (out percent);

					var spinner = builder.get_object ("spinner") as Spinner;

					spinner.active = percent < 100 ? true : false;
					playbin.set_state (percent == 100 ? State.PLAYING : State.PAUSED);
					break;
				default:
					break;
			}
			return true;
		});

		window.key_press_event.connect ((event) => {
			switch (event.keyval) {
				case Key.KP_Add:
				case Key.plus:
					volume.set_value (volume.get_value () + 0.0125);
					break;
				case Key.KP_Subtract:
				case Key.minus:
					volume.set_value (volume.get_value () - 0.0125);
					break;
				case Key.Escape:
					window.unfullscreen ();
					break;
				case Key.F11:
					if ((window.get_window ().get_state () & WindowState.FULLSCREEN) != 0)
						window.unfullscreen ();
					else
						window.fullscreen ();
					break;
				default:
					return false;
			}
			return true;
		});

		window.delete_event.connect (() => {
			window.remove (sink.widget);
			playbin.set_state (State.NULL);
			return false;
		});

		var button = builder.get_object ("channel_button") as Button;
		button.clicked();
	}

	void get_access_token (Soup.Session session, Soup.Message msg) {
		var parser = new Json.Parser ();
		try {
			parser.load_from_data ((string) msg.response_body.data);
		} catch (Error e) {
			warning (e.message);
		}

		var root_object = parser.get_root ().get_object ();

		if (root_object.get_int_member ("_total") != 1) {
			var dialog = new MessageDialog (get_active_window (), DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, ButtonsType.CLOSE, "No such channel");
			dialog.run ();
			dialog.destroy ();
			return;
		}

		var header_bar = window.get_titlebar () as HeaderBar;

		header_bar.subtitle = root_object.get_array_member ("users").get_object_element (0).get_string_member ("display_name");
		var id = root_object.get_array_member ("users").get_object_element (0).get_string_member ("_id");

		var message = new Soup.Message ("GET", "https://api.twitch.tv/kraken/streams/?channel=" + id);
		message.request_headers.append ("Client-ID", client_id_priv);
		message.request_headers.append ("Accept", "application/vnd.twitchtv.v5+json");

		session.queue_message (message, online_check);
	}

	void online_check (Soup.Session session, Soup.Message msg) {
		var parser = new Json.Parser ();
		try {
			parser.load_from_data ((string) msg.response_body.data);
		} catch (Error e) {
			warning (e.message);
		}

		var root_object = parser.get_root ().get_object ();
		var stream_count = root_object.get_array_member ("streams").get_length ();

		if (stream_count != 1) {
			var dialog = new MessageDialog (get_active_window (), DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, ButtonsType.CLOSE, "Channel offline");
			dialog.run ();
			dialog.destroy ();
			return;
		}

		var message = new Soup.Message ("POST", "https://gql.twitch.tv/gql");
		message.request_headers.append ("Client-ID", client_id);
		message.request_headers.append ("Content-Type", "application/json");
		message.request_headers.append ("origin", "https://player.twitch.tv");
		message.request_headers.append ("referer", "https://player.twitch.tv");

		var json = "{
			\"operationName\": \"PlaybackAccessToken\",
			\"extensions\": {
				\"persistedQuery\": {
					\"version\": 1,
					\"sha256Hash\": \"0828119ded1c13477966434e15800ff57ddacf13ba1911c129dc2200705b0712\"
				}
			},
			\"variables\": {
				\"isLive\": true,
				\"login\": \"" + channel + "\",
				\"isVod\": false,
				\"vodID\": \"\",
				\"playerType\": \"embed\"
			}
		}";
		message.request_body.append_take (json.data);

		session.queue_message (message, play_stream);
	}

	void play_stream (Soup.Session session, Soup.Message msg) {
		var parser = new Json.Parser ();
		try {
			parser.load_from_data ((string) msg.response_body.data);
		} catch (Error e) {
			warning (e.message);
		}

		var object = parser.get_root ().get_object ().get_object_member ("data").get_object_member ("streamPlaybackAccessToken");

		var sig = object.get_string_member ("signature");
		var token = object.get_string_member ("value");

		var uri = "http://usher.twitch.tv/api/channel/hls/" +
			channel + ".m3u8?" +
			"player=twitchweb&" +
			"token=" + Soup.URI.encode (token, null) + "&" +
			"sig=" + Soup.URI.encode (sig, null) + "&" +
			"allow_audio_only=false&allow_source=true&type=any&p=" + Random.int_range (0, 999999).to_string ();

		playbin.set_state (State.READY);
		playbin.uri = uri;
		playbin.set_state (State.PAUSED);
	}

	static int main (string[] args) {
		X.init_threads ();

		if (Environment.get_variable ("GST_VAAPI_ALL_DRIVERS") == "0")
			Environment.unset_variable ("GST_VAAPI_ALL_DRIVERS");
		else
			Environment.set_variable ("GST_VAAPI_ALL_DRIVERS", "1", false);

		Gst.init (ref args);

		var nvdec = Registry.get ().lookup_feature ("nvdec");
		if (nvdec != null)
			nvdec.set_rank (Rank.PRIMARY << 1);

		var vah264dec = Registry.get ().lookup_feature ("vah264dec");
		if (vah264dec != null)
			vah264dec.set_rank (Rank.PRIMARY << 1);

		return new TwitTwatApp ().run (args);
	}
}
