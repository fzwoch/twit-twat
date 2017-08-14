/*
 * Twit-Twat
 *
 * Copyright (C) 2017 Florian Zwoch <fzwoch@gmail.com>
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

class TwitTwatApp : Gtk.Application {
	private string channel = "";
	private const string client_id = "7ikopbkspr7556owm9krqmalvr2w0i4";
	private uint64 connection_speed = 0;
	private dynamic Gst.Element playbin = null;
	private Gtk.ApplicationWindow window = null;

	public override void activate () {
		var css = new Gtk.CssProvider ();
		try {
			css.load_from_data ("window window { background-color: black; }");
		} catch (GLib.Error e) {
			warning (e.message);
		}

		Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

		window = new Gtk.ApplicationWindow (this);
		window.title = "Twit-Twat";
		window.hide_titlebar_when_maximized = true;
		window.set_default_size (960, 540);
		window.show_all ();

		window.button_press_event.connect ((event) => {
			if (event.type == Gdk.EventType.DOUBLE_BUTTON_PRESS && event.button == 1) {
				if ((window.get_window ().get_state () & Gdk.WindowState.MAXIMIZED) != 0)
					window.unmaximize ();
				else if ((window.get_window ().get_state () & Gdk.WindowState.FULLSCREEN) != 0)
					window.unfullscreen ();
				else
					window.fullscreen ();
				return true;
			}
			return false;
		});

		window.key_press_event.connect ((event) => {
			switch (event.keyval) {
				case Gdk.Key.KP_Add:
				case Gdk.Key.plus:
					if (playbin == null)
						break;
					double volume = playbin.volume;
					volume += 0.0125;
					if (volume > 1.0)
						volume = 1.0;
					playbin.volume = volume;
					break;
				case Gdk.Key.KP_Subtract:
				case Gdk.Key.minus:
					if (playbin == null)
						break;
					double volume = playbin.volume;
					volume -= 0.0125;
					if (volume < 0.0)
						volume = 0.0;
					playbin.volume = volume;
					break;
				case Gdk.Key.Escape:
					window.unmaximize ();
					window.unfullscreen ();
					break;
				case Gdk.Key.q:
					window.close ();
					break;
				case Gdk.Key.g:
					var entry = new Gtk.Entry ();
					var dialog = new Gtk.Dialog.with_buttons ("Enter channel", window, Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT, null);
					dialog.get_content_area ().add (entry);
					dialog.resizable = false;
					entry.text = channel;
					entry.activate.connect (() => {
						if (entry.text != "") {
							channel = entry.text.down ();
							GLib.Idle.add (() => {
								var session = new Soup.Session ();
								var message = new Soup.Message ("GET", "https://api.twitch.tv/kraken/streams?channel=" + channel);

								message.request_headers.append ("Client-ID", client_id);
								session.ssl_strict = false;
								session.queue_message (message, get_access_token);
								return false;
							});
						}
						dialog.destroy ();
					});
					dialog.show_all ();
					break;
				default:
					return false;
			}
			return true;
		});

		window.destroy.connect ((event) => {
			if (playbin != null) {
				playbin.set_state (Gst.State.NULL);
				playbin = null;
			}
		});
	}

	private void get_access_token (Soup.Session session, Soup.Message msg) {
		var parser = new Json.Parser ();
		try {
			parser.load_from_data ((string) msg.response_body.data);
		} catch (GLib.Error e) {
			warning (e.message);
		}

		var reader = new Json.Reader (parser.get_root ());

		reader.read_member ("_total");
		var total = reader.get_int_value ();
		reader.end_member ();

		if (total != 1) {
			var dialog = new Gtk.MessageDialog (window, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.INFO, Gtk.ButtonsType.CLOSE, "Channel offline");
			dialog.run ();
			dialog.destroy ();
			return;
		}

		var message = new Soup.Message ("GET", "https://api.twitch.tv/api/channels/" + channel + "/access_token");
		message.request_headers.append ("Client-ID", client_id);
		session.queue_message (message, play_stream);
	}

	private void play_stream (Soup.Session session, Soup.Message message) {
		var parser = new Json.Parser ();
		try {
			parser.load_from_data ((string) message.response_body.data);
		} catch (GLib.Error e) {
			warning (e.message);
		}

		var reader = new Json.Reader (parser.get_root ());

		reader.read_member ("sig");
		var sig = reader.get_string_value ();
		reader.end_member ();

		reader.read_member ("token");
		var token = reader.get_string_value ();
		reader.end_member ();

		var rand = new GLib.Rand ();

		var uri = "http://usher.twitch.tv/api/channel/hls/" +
			channel + ".m3u8?" +
			"player=twitchweb&" +
			"token=" + token + "&" +
			"sig=" + sig + "&" +
			"allow_audio_only=true&allow_source=true&type=any&p=" + rand.int_range (0, 999999).to_string ();

		if (playbin != null) {
			playbin.set_state (Gst.State.NULL);
			playbin = null;
		}

		playbin = Gst.ElementFactory.make ("playbin", null);

		var overlay = playbin as Gst.Video.Overlay;
		var win = window.get_window () as Gdk.X11.Window;
		overlay.set_window_handle ((uint*)win.get_xid ());

		playbin.get_bus ().add_watch (GLib.Priority.DEFAULT, (bus, message) => {
			switch (message.type) {
				case Gst.MessageType.EOS:
					playbin.set_state (Gst.State.NULL);
					var dialog = new Gtk.MessageDialog (window, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.INFO, Gtk.ButtonsType.CLOSE, "Broadcast finished");
					dialog.run ();
					dialog.destroy ();
					break;
				case Gst.MessageType.WARNING:
					GLib.Error err;
					message.parse_warning (out err, null);
					warning (err.message);
					break;
				case Gst.MessageType.ERROR:
					GLib.Error err;
					playbin.set_state (Gst.State.NULL);
					message.parse_error (out err, null);
					var dialog = new Gtk.MessageDialog (window, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, err.message);
					dialog.run ();
					dialog.destroy ();
					break;
				case Gst.MessageType.BUFFERING:
					int percent = 0;
					message.parse_buffering (out percent);
					Gst.State state = Gst.State.NULL;
					playbin.get_state (out state, null, Gst.CLOCK_TIME_NONE);
					if (percent < 100 && state == Gst.State.PLAYING)
						playbin.set_state (Gst.State.PAUSED);
					else if (percent == 100 && state != Gst.State.PLAYING)
						playbin.set_state (Gst.State.PLAYING);
					break;
				default:
					break;
			}
			return true;
		});

		playbin.uri = uri;
		playbin.latency = 2 * Gst.SECOND;
		playbin.connection_speed = connection_speed;
		playbin.set_state (Gst.State.PAUSED);
	}

	static int main (string[] args) {
		Gtk.init (ref args);
		Gst.init (ref args);

		return new TwitTwatApp ().run (args);
	}
}
