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
	static string channel = "";
	static string client_id = "";

	const GLib.OptionEntry[] options = {
		{ "channel", 0, 0, GLib.OptionArg.STRING, ref channel, "Twitch.tv channel name", "CHANNEL" },
		{ "client-id", 0, 0, GLib.OptionArg.STRING, ref client_id, "Twitch.tv Client-ID", "CLIENT-ID" },
		{ null }
	};

	private dynamic Gtk.ApplicationWindow window = null;
	private bool fullscreen_state = false;

	private TwitTwatApp () {
		Object (application_id: "zwoch.florian.twit-twat", flags: ApplicationFlags.FLAGS_NONE);
	}

	private void on_element (Gst.Element playbin, Gst.Element element) {
		var factory = element.get_factory ();

		if (factory == null) {
			return;
		}

		dynamic Gst.Element e = element;

		if (factory.get_name () == "souphttpsrc") {
			var val = GLib.Value(typeof(string));
			val.set_string(client_id);

			var headers = new Gst.Structure.empty("client-id");
			headers.set_value("Client-ID", val);

			e.ssl_strict = false;
			e.extra_headers = headers;
		}
	}

	public override void activate () {
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", "https://api.twitch.tv/api/channels/" + channel + "/access_token");

		message.request_headers.append ("Client-ID", client_id);

		InputStream stream = null;
		try {
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

		print("token: %s\n",token);

		var rand = new GLib.Rand ();

		string uri = "http://usher.twitch.tv/api/channel/hls/" +
			channel + ".m3u8?" +
			"player=twitchweb&" +
			"token=" + token + "&" +
			"sig=" + sig + "&" +
			"allow_audio_only=true&allow_source=true&type=any&p=" + rand.int_range(0, 999999).to_string ();

		var css = new Gtk.CssProvider ();
		try {
			css.load_from_data ("* {background-color: black;}");
		} catch (GLib.Error e) {
			warning (e.message);
		}

		Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

		window = new Gtk.ApplicationWindow (this);
		window.title = "Twit-Twat";
		window.set_hide_titlebar_when_maximized (true);
		window.set_default_size (960, 540);
		window.set_position (Gtk.WindowPosition.CENTER);
		window.show_all ();

		window.button_press_event.connect ((event) => {
			if (event.type == Gdk.EventType.DOUBLE_BUTTON_PRESS && event.button == 1) {
				if (fullscreen_state == false)
					window.fullscreen ();
				else
					window.unfullscreen ();
				return true;
			}
			return false;
		});

		window.window_state_event.connect ((event) => {
			if (event.changed_mask == Gdk.WindowState.FULLSCREEN) {
				fullscreen_state = !fullscreen_state;
				return true;
			}
			return false;
		});

		window.destroy.connect ((event) => {
			print ("FIXME: stop pipeline\n");
		});

		window.key_press_event.connect ((source, key) => {
			if (key.keyval == Gdk.Key.Escape && fullscreen_state == true) {
				window.unfullscreen ();
				return true;
			}
			return false;
		});

		dynamic Gst.Element playbin = Gst.ElementFactory.make ("playbin", null);
		dynamic Gst.Element gtksink = Gst.ElementFactory.make ("gtkglsink", null);

		Gtk.Widget widget = gtksink.widget;
		window.add (widget);
		widget.show ();

		playbin.element_setup.connect (on_element);
		playbin.video_sink = gtksink;
		playbin.uri = uri;
		playbin.set_state (Gst.State.PLAYING);
	}

	public static int main (string[] args) {
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
