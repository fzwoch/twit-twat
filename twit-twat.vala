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
	dynamic Element playbin = null;
	VolumeButton volume = null;
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

		volume = builder.get_object ("volume") as VolumeButton;
		volume.value_changed.connect ((value) => {
			playbin.volume = value;
		});

		var bitrate = builder.get_object ("bitrate") as Scale;
		bitrate.value_changed.connect ((range) => {
			playbin.connection_speed = (int) range.get_value ();
		});
		bitrate.format_value.connect ((scale, value) => {
			return "%.0f kbps".printf (value);
		});

		var entry = builder.get_object ("channel") as Entry;
		entry.activate.connect ((entry) => {
			channel = entry.text.strip ().down ();

			var popover = builder.get_object ("popover_channel") as Popover;
			popover.hide ();

			try {
				var p = new Subprocess (SubprocessFlags.STDOUT_PIPE , "streamlink", "--json", "--stream-url", "twitch.tv/" + channel, "best");
				p.wait_check_async.begin (null, (obj, res) => {
					var buffer = new uint8[8192];
					try {
						p.get_stdout_pipe ().read (buffer);
					} catch (IOError e) {
						warning (e.message);
					}

					var parser = new Json.Parser ();
					try {
							parser.load_from_data ((string) buffer);
					} catch (Error e) {
							warning (e.message);
					}

					var header_bar = window.get_titlebar () as HeaderBar;
					header_bar.subtitle =parser.get_root ().get_object ().get_object_member ("metadata").get_string_member ("author");

					playbin.set_state (State.READY);
					playbin.uri = parser.get_root ().get_object ().get_string_member ("url");
					playbin.volume = volume.value;
					playbin.set_state (State.PAUSED);
				});
			} catch (Error e) {
				warning (e.message);
			}
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
