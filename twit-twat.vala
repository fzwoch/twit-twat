/*
 * Twit-Twat
 *
 * Copyright (C) 2017-2018 Florian Zwoch <fzwoch@gmail.com>
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
	const string client_id = "7ikopbkspr7556owm9krqmalvr2w0i4";
	uint64 connection_speed = 0;
	dynamic Element playbin = null;
	ApplicationWindow window = null;

	public override void activate () {
		window = new ApplicationWindow (this);
		window.title = "Twit-Twat";
		window.hide_titlebar_when_maximized = true;
		window.set_default_size (960, 540);

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
					playbin.set_state (State.NULL);
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
					playbin.set_state (State.NULL);
					message.parse_error (out err, null);
					var dialog = new MessageDialog (window, DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, ButtonsType.CLOSE, err.message);
					dialog.run ();
					dialog.destroy ();
					break;
				case Gst.MessageType.BUFFERING:
					int percent = 0;
					message.parse_buffering (out percent);
					State state = State.NULL;
					playbin.get_state (out state, null, CLOCK_TIME_NONE);
					if (percent < 100 && state == State.PLAYING)
						playbin.set_state (State.PAUSED);
					else if (percent == 100 && state != State.PLAYING)
						playbin.set_state (State.PLAYING);
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
							var message = new Soup.Message ("GET", "https://api.twitch.tv/helix/streams?user_login=" + channel);

							message.request_headers.append ("Client-ID", client_id);
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
					entry.text = connection_speed.to_string ();
					entry.activate.connect (() => {
						connection_speed = int.parse (entry.text);
						dialog.destroy ();
					});
					dialog.show_all ();
					break;
				case Key.H:
				case Key.h:
					var dialog = new MessageDialog.with_markup (window, DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.INFO, ButtonsType.CLOSE,
						"<b>G</b>\t\tGo to channel\n<b>+/-</b>\t\tChange volume\n<b>D-Click</b>\tToggle full screen\n<b>Esc</b>\t\tExit full screen\n<b>S</b>\t\tSet bandwidth limit\n<b>H</b>\t\tControls info\n<b>Q</b>\t\tQuit"
					);
					dialog.title = "Controls";
					dialog.run ();
					dialog.destroy ();
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

		var reader = new Json.Reader (parser.get_root ());

		reader.read_member ("data");
		var total = reader.count_elements ();
		reader.end_member ();

		if (total == 0) {
			var dialog = new MessageDialog (window, DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.INFO, ButtonsType.CLOSE, "Channel offline");
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

		var reader = new Json.Reader (parser.get_root ());

		reader.read_member ("sig");
		var sig = reader.get_string_value ();
		reader.end_member ();

		reader.read_member ("token");
		var token = reader.get_string_value ();
		reader.end_member ();

		var uri = "http://usher.twitch.tv/api/channel/hls/" +
			channel + ".m3u8?" +
			"player=twitchweb&" +
			"token=" + token + "&" +
			"sig=" + sig + "&" +
			"allow_audio_only=true&allow_source=true&type=any&p=" + Random.int_range (0, 999999).to_string ();

		playbin.set_state (State.NULL);
		playbin.uri = uri;
		playbin.connection_speed = connection_speed;
		playbin.set_state (State.PAUSED);
	}

	static int main (string[] args) {
		Environment.set_variable ("GST_VAAPI_ALL_DRIVERS", "1", true);
		X.init_threads ();
		Gst.init (ref args);

		var nvdec = Registry.get ().lookup_feature ("nvdec");
		if (nvdec != null)
			nvdec.set_rank (Rank.PRIMARY << 1);

		return new TwitTwatApp ().run (args);
	}
}
