/*
 * Twit-Twat
 *
 * Copyright (C) 2017-2020 Florian Zwoch <fzwoch@gmail.com>
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
	string display_name = "";
	const string client_id_priv = "7ikopbkspr7556owm9krqmalvr2w0i4";
	const string client_id = "kimne78kx3ncx6brgo4mv6wki5h1ko";
	dynamic Element playbin = null;
	ApplicationWindow window = null;

	public override void activate () {
		window = new ApplicationWindow (this);
		window.hide_titlebar_when_maximized = true;
		window.set_default_size (960, 540);

		var header_bar = new Gtk.HeaderBar ();
		header_bar.show_close_button = true;
		header_bar.title = "Twit-Twat";
		window.set_titlebar (header_bar);

		var sink = ElementFactory.make ("gtkglsink", null) as dynamic Element;

		window.add (sink.widget);
		window.show_all ();

		var bin = ElementFactory.make ("glsinkbin", null) as dynamic Element;
		bin.sink = sink;

		playbin = ElementFactory.make ("playbin", null);
		playbin.video_sink = bin;

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

					header_bar.subtitle = display_name;
					if (percent < 100)
						header_bar.subtitle += " [" + percent.to_string () + "%]";
					playbin.set_state (percent == 100 ? State.PLAYING : State.PAUSED);
					break;
				default:
					break;
			}
			return true;
		});

		window.button_press_event.connect ((event) => {
			if (event.type == Gdk.EventType.DOUBLE_BUTTON_PRESS && event.button == BUTTON_PRIMARY) {
				if ((window.get_window ().get_state () & WindowState.MAXIMIZED) != 0)
					window.unmaximize ();
				else if ((window.get_window ().get_state () & WindowState.FULLSCREEN) != 0)
					window.unfullscreen ();
				else
					window.fullscreen ();
				return true;
			}
			return false;
		});

		window.key_press_event.connect ((event) => {
			switch (event.keyval) {
				case Key.KP_Add:
				case Key.plus:
					if (playbin == null)
						break;
					double volume = playbin.volume;
					volume += 0.0125;
					playbin.volume = volume.clamp (0.0, 1.0);
					break;
				case Key.KP_Subtract:
				case Key.minus:
					if (playbin == null)
						break;
					double volume = playbin.volume;
					volume -= 0.0125;
					playbin.volume = volume.clamp (0.0, 1.0);
					break;
				case Key.Escape:
					window.unmaximize ();
					window.unfullscreen ();
					break;
				case Key.F11:
					if ((window.get_window ().get_state () & WindowState.FULLSCREEN) != 0)
						window.unfullscreen ();
					else
						window.fullscreen ();
					break;
				case Key.Q:
				case Key.q:
					window.close ();
					break;
				case Key.G:
				case Key.g:
					var entry = new Entry ();
					var dialog = new Dialog.with_buttons ("Enter channel", window, DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT, null);
					dialog.get_content_area ().add (entry);
					dialog.resizable = false;
					entry.text = channel;
					entry.activate.connect (() => {
						if (entry.text != "") {
							channel = entry.text.strip ().down ();

							var session = new Soup.Session ();
							var message = new Soup.Message ("GET", "https://api.twitch.tv/kraken/users?login=" + channel);

							message.request_headers.append ("Client-ID", client_id_priv);
							message.request_headers.append ("Accept", "application/vnd.twitchtv.v5+json");

							session.ssl_strict = false;
							session.queue_message (message, get_access_token);
						}
						dialog.destroy ();
					});
					dialog.show_all ();
					break;
				case Key.S:
				case Key.s:
					var entry = new Entry ();
					var dialog = new Dialog.with_buttons ("Max kbps", window, DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT, null);
					dialog.get_content_area ().add (entry);
					dialog.resizable = false;
					uint64 connection_speed = playbin.connection_speed;
					entry.text = connection_speed.to_string ();
					entry.activate.connect (() => {
						playbin.connection_speed = int.parse (entry.text);
						dialog.destroy ();
					});
					dialog.show_all ();
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

		var event = new Gdk.Event (Gdk.EventType.KEY_PRESS);
		event.key.keyval = Key.g;
		event.key.window = window.get_window ();
		event.set_device (Display.get_default ().get_default_seat ().get_keyboard ());
		event.put ();
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
			var dialog = new MessageDialog (window, DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, ButtonsType.CLOSE, "No such channel");
			dialog.run ();
			dialog.destroy ();
			return;
		}

		display_name = root_object.get_array_member ("users").get_object_element (0).get_string_member ("display_name");
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
			var dialog = new MessageDialog (window, DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, ButtonsType.CLOSE, "Channel offline");
			dialog.run ();
			dialog.destroy ();
			return;
		}

		var message = new Soup.Message ("GET", "https://api.twitch.tv/api/channels/" + channel + "/access_token");
		message.request_headers.append ("Client-ID", client_id);

		session.queue_message (message, play_stream);
	}

	void play_stream (Soup.Session session, Soup.Message message) {
		var parser = new Json.Parser ();
		try {
			parser.load_from_data ((string) message.response_body.data);
		} catch (Error e) {
			warning (e.message);
		}

		var root_object = parser.get_root ().get_object ();

		var sig = root_object.get_string_member ("sig");
		var token = root_object.get_string_member ("token");

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
