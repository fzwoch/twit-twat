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
	private static string channel = "";
	private static string client_id = "7ikopbkspr7556owm9krqmalvr2w0i4";
	private static uint64 connection_speed = 0;
	private dynamic Gst.Element playbin = null;

	private const GLib.OptionEntry[] options = {
		{ "channel", 0, 0, GLib.OptionArg.STRING, ref channel, "Twitch.tv channel name", "CHANNEL" },
		{ "client-id", 0, 0, GLib.OptionArg.STRING, ref client_id, "Twitch.tv Client-ID", "CLIENT-ID" },
		{ "connection-speed", 0, 0, GLib.OptionArg.INT64, ref connection_speed, "Limit connection bandwidth (kbps)", "BITRATE" },
		{ null }
	};

	public override void activate () {
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", "https://api.twitch.tv/api/channels/" + channel + "/access_token");

		message.request_headers.append ("Client-ID", client_id);

		InputStream stream = null;
		try {
			session.ssl_strict = false;
			stream = session.send (message);
		} catch (GLib.Error e) {
			warning (e.message);
		}

		var data_stream = new DataInputStream (stream);
		var parser = new Json.Parser ();
		try {
			parser.load_from_stream (data_stream);
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

		string uri = "http://usher.twitch.tv/api/channel/hls/" +
			channel + ".m3u8?" +
			"player=twitchweb&" +
			"token=" + token + "&" +
			"sig=" + sig + "&" +
			"allow_audio_only=true&allow_source=true&type=any&p=" + rand.int_range (0, 999999).to_string ();

		var css = new Gtk.CssProvider ();
		try {
			css.load_from_data ("window window { background-color: black; }");
		} catch (GLib.Error e) {
			warning (e.message);
		}

		Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

		var window = new Gtk.ApplicationWindow (this);
		window.title = "Twit-Twat";
		window.set_hide_titlebar_when_maximized (true);
		window.set_default_size (960, 540);
		window.set_position (Gtk.WindowPosition.CENTER);
		window.show_all ();

		window.button_press_event.connect ((event) => {
			if (event.type == Gdk.EventType.DOUBLE_BUTTON_PRESS && event.button == 1) {
				if ((window.get_window ().get_state () & Gdk.WindowState.FULLSCREEN) == 0)
					window.fullscreen ();
				else
					window.unfullscreen ();
				return true;
			}
			return false;
		});

		window.key_press_event.connect ((event) => {
			switch (event.keyval) {
				case Gdk.Key.KP_Add:
				case Gdk.Key.plus:
					double volume = playbin.volume;
					volume += 0.0125;
					if (volume > 1.0)
						volume = 1.0;
					playbin.volume = volume;
					break;
				case Gdk.Key.KP_Subtract:
				case Gdk.Key.minus:
					double volume = playbin.volume;
					volume -= 0.0125;
					if (volume < 0.0)
						volume = 0.0;
					playbin.volume = volume;
					break;
				case Gdk.Key.Escape:
					window.unfullscreen ();
					break;
				case Gdk.Key.q:
					window.close ();
					break;
				default:
					return false;
			}
			return true;
		});

		window.destroy.connect ((event) => {
			playbin.set_state (Gst.State.NULL);
			playbin = null;
		});

		playbin = Gst.ElementFactory.make ("playbin", null);
		playbin.get_bus ().set_sync_handler ((bus, message) => {
			if (Gst.Video.is_video_overlay_prepare_window_handle_message (message)) {
				var overlay = message.src as Gst.Video.Overlay;
				var win = window.get_window () as Gdk.X11.Window;
				overlay.set_window_handle ((uint*)win.get_xid ());
			}
			switch (message.type) {
				case Gst.MessageType.EOS:
					GLib.Idle.add (() => {
						playbin.set_state (Gst.State.NULL);
						var dialog = new Gtk.MessageDialog (window, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.INFO, Gtk.ButtonsType.CLOSE, "Broadcast finished");
						dialog.run ();
						dialog.destroy ();
						return false;
					});
					break;
				case Gst.MessageType.WARNING:
					GLib.Error err;
					message.parse_warning (out err, null);
					warning (err.message + "\n");
					break;
				case Gst.MessageType.ERROR:
					GLib.Error err;
					message.parse_error (out err, null);
					GLib.Idle.add (() => {
						var dialog = new Gtk.MessageDialog (window, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, err.message);
						dialog.run ();
						dialog.destroy ();
						return false;
					});
					break;
				case Gst.MessageType.BUFFERING:
					int percent = 0;
					message.parse_buffering(out percent);
					GLib.Idle.add (() => {
						Gst.State state = Gst.State.NULL;
						playbin.get_state (out state, null, Gst.CLOCK_TIME_NONE);
						if (percent < 100 && state == Gst.State.PLAYING)
							playbin.set_state (Gst.State.PAUSED);
						else if (percent == 100 && state == Gst.State.PAUSED)
							playbin.set_state (Gst.State.PLAYING);
						return false;
					});
					break;
				default:
					break;
			}
			message.unref ();
			return Gst.BusSyncReply.DROP;
		});

		playbin.uri = uri;
		playbin.latency = 4 * Gst.SECOND;
		playbin.connection_speed = connection_speed;
		playbin.set_state (Gst.State.PAUSED);
	}

	static int main (string[] args) {
		Gtk.init (ref args);
		Gst.init (ref args);

		var app = new TwitTwatApp ();

		try {
			var opt_context = new OptionContext (null);
			opt_context.add_main_entries (options, null);
			opt_context.parse (ref args);
		} catch (GLib.OptionError e) {
		}
		channel = channel.down ();

		return app.run (args);
	}
}
