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
	private Gtk.DrawingArea area = null;

	private void element_setup (Gst.Element playbin, dynamic Gst.Element element) {
		if (element.get_factory () == Gst.ElementFactory.find ("glimagesink"))
			element.handle_events = false;
	}

	public override void activate () {
		window = new Gtk.ApplicationWindow (this);
		window.title = "Twit-Twat";
		window.hide_titlebar_when_maximized = true;
		window.set_default_size (960, 540);

		area = new Gtk.DrawingArea ();
		area.add_events (Gdk.EventMask.BUTTON_PRESS_MASK);

		area.draw.connect ((cr) => {
			if (playbin != null) {
				Gst.State state = Gst.State.NULL;
				playbin.get_state (out state, null, Gst.CLOCK_TIME_NONE);
				if (state == Gst.State.NULL)
					cr.paint ();
				return true;
			}
			return false;
		});

		window.add (area);
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
					playbin.volume = volume.clamp (0.0, 1.0);
					break;
				case Gdk.Key.KP_Subtract:
				case Gdk.Key.minus:
					if (playbin == null)
						break;
					double volume = playbin.volume;
					volume -= 0.0125;
					playbin.volume = volume.clamp (0.0, 1.0);
					break;
				case Gdk.Key.Escape:
					window.unmaximize ();
					window.unfullscreen ();
					break;
				case Gdk.Key.Q:
				case Gdk.Key.q:
					if (playbin != null) {
						playbin.set_state (Gst.State.NULL);
						playbin = null;
					}
					window.close ();
					break;
				case Gdk.Key.G:
				case Gdk.Key.g:
					var entry = new Gtk.Entry ();
					var dialog = new Gtk.Dialog.with_buttons ("Enter channel", window, Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT, null);
					dialog.get_content_area ().add (entry);
					dialog.resizable = false;
					entry.text = channel;
					entry.activate.connect (() => {
						if (entry.text != "") {
							channel = entry.text.strip ().down ();

							var session = new Soup.Session ();
							var message = new Soup.Message ("GET", "https://api.twitch.tv/kraken/streams?channel=" + channel);

							message.request_headers.append ("Client-ID", client_id);
							session.ssl_strict = false;
							session.queue_message (message, get_access_token);
						}
						dialog.destroy ();
					});
					dialog.show_all ();
					break;
				case Gdk.Key.S:
				case Gdk.Key.s:
					var entry = new Gtk.Entry ();
					var dialog = new Gtk.Dialog.with_buttons ("Max kbps", window, Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT, null);
					dialog.get_content_area ().add (entry);
					dialog.resizable = false;
					entry.text = connection_speed.to_string ();
					entry.activate.connect (() => {
						connection_speed = int.parse (entry.text);
						dialog.destroy ();
					});
					dialog.show_all ();
					break;
				case Gdk.Key.H:
				case Gdk.Key.h:
					var dialog = new Gtk.MessageDialog.with_markup (window, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.INFO, Gtk.ButtonsType.CLOSE,
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

		var event = new Gdk.Event (Gdk.EventType.KEY_PRESS);
		event.key.keyval = Gdk.Key.g;
		event.key.window = window.get_window ();
		event.set_device (Gdk.Display.get_default ().get_default_seat ().get_keyboard ());
		event.put ();
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

		if (area.get_window () is Gdk.X11.Window) {
			var win = area.get_window () as Gdk.X11.Window;
			overlay.set_window_handle ((uint*)win.get_xid ());
		}
		// FIXME: else wayland..

		playbin.element_setup.connect (element_setup);

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

		var nvdec = Gst.Registry.get ().lookup_feature ("nvdec");
		if (nvdec != null)
			nvdec.set_rank (Gst.Rank.PRIMARY << 1);

		return new TwitTwatApp ().run (args);
	}
}
