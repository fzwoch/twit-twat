//
// Twit-Twat
//
// Copyright (C) 2017-2024 Florian Zwoch <fzwoch@gmail.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.
//

void main(string[] args) {
	Gst.init(ref args);

	var app = new Adw.Application(null, ApplicationFlags.DEFAULT_FLAGS);

	app.activate.connect(() => {
		var builder = new Gtk.Builder.from_resource("/twit-twat/twit-twat.ui");

		var window = builder.get_object("window") as Adw.ApplicationWindow;
		var picture = builder.get_object("picture") as Gtk.Picture;
		var channel = builder.get_object("channel") as Gtk.Entry;
		var revealer = builder.get_object("revealer") as Gtk.Revealer;
		var spinner = builder.get_object("spinner") as Gtk.Spinner;
		var volume = builder.get_object("volume") as Gtk.ScaleButton;
		var toast = builder.get_object("toast") as Adw.ToastOverlay;

		app.add_window(window);
		window.present();

		var pipeline = new Gst.Pipeline(null);

		var playbin = Gst.ElementFactory.make("playbin3", null) as dynamic Gst.Element;
		var gtksink = Gst.ElementFactory.make("gtk4paintablesink", null) as dynamic Gst.Element;

		pipeline.add(playbin);

		playbin.instant_uri = true;
		playbin.video_sink = gtksink;

		picture.paintable = gtksink.paintable;

		playbin.volume = volume.adjustment.value / 100.0;
		volume.value_changed.connect(() => {
			playbin.volume = volume.adjustment.value / 100.0;
		});

		pipeline.get_bus().add_watch(Priority.DEFAULT, (bus, message) => {
			switch (message.type) {
				case Gst.MessageType.WARNING:
					Error err;
					message.parse_warning(out err, null);
					var t = new Adw.Toast(err.message);
					t.timeout = 3;
					toast.add_toast(t);
					break;
				case Gst.MessageType.ERROR:
					Error err;
					message.parse_error(out err, null);
					var t = new Adw.Toast(err.message);
					t.priority = Adw.ToastPriority.HIGH;
					t.timeout = 0;
					toast.add_toast(t);
					pipeline.set_state(Gst.State.NULL);
					break;
				case Gst.MessageType.EOS:
					var t = new Adw.Toast("Stream ended.");
					t.priority = Adw.ToastPriority.HIGH;
					t.timeout = 0;
					toast.add_toast(t);
					break;
				case Gst.MessageType.BUFFERING:
					int percent;
					message.parse_buffering(out percent);

					if (spinner.spinning && percent == 100)
						pipeline.set_state(Gst.State.PLAYING);
					else if (!spinner.spinning && percent != 100)
						pipeline.set_state(Gst.State.PAUSED);

					spinner.spinning = percent < 100 ? true : false;
					break;
				default:
					break;
			}
			return true;
		});

		channel.activate.connect(() => {
			window.set_focus(null);
			channel.sensitive = false;
			try {
				var p = new Subprocess(SubprocessFlags.STDOUT_PIPE , "streamlink", "--json", "--stream-url", (channel.text.strip().down().has_prefix("@") ? "youtube.com/" : "twitch.tv/") + channel.text.strip().down(), "best");
				p.wait_check_async.begin(null, (obj, res) => {
					var buffer = new uint8[8192];
					try {
						p.get_stdout_pipe().read(buffer);
					} catch (IOError e) {
						var t = new Adw.Toast(e.message);
						t.priority = Adw.ToastPriority.HIGH;
						t.timeout = 0;
						toast.add_toast(t);
						return;
					}

					var parser = new Json.Parser();
					try {
						parser.load_from_data((string) buffer);
					} catch (Error e) {
						var t = new Adw.Toast(e.message);
						t.priority = Adw.ToastPriority.HIGH;
						t.timeout = 0;
						toast.add_toast(t);
						return;
					}

					if (parser.get_root().get_object().has_member("error")) {
						var t = new Adw.Toast(parser.get_root().get_object().get_string_member("error"));
						t.priority = Adw.ToastPriority.HIGH;
						toast.add_toast(t);
						channel.sensitive = true;
						channel.grab_focus();
						return;
					}

					var title = builder.get_object("title") as Adw.WindowTitle;
					title.subtitle = parser.get_root().get_object().get_object_member("metadata").get_string_member("author");

					playbin.uri = parser.get_root().get_object().get_string_member("master").replace("allow_audio_only=true", "allow_audio_only=false");
					pipeline.set_state(Gst.State.PLAYING);

					channel.text = "";
					channel.sensitive = true;
				});
			} catch (Error e) {
				var t = new Adw.Toast(e.message);
				t.priority = Adw.ToastPriority.HIGH;
				t.timeout = 0;
				toast.add_toast(t);
			}
		});

		uint id = 0;
		double last_x = 0;
		double last_y = 0;

		void timer() {
			if (id != 0) {
				GLib.Source.remove(id);
			}
			id = GLib.Timeout.add_seconds(3, () => {
				if (volume.active) {
					return true;
				}
				revealer.reveal_child = false;
				id = 0;
				return false;
			});
			revealer.reveal_child = true;
		}

		var mouse = new Gtk.EventControllerMotion();
		mouse.motion.connect((x, y) => {
			if (x == last_x && y == last_y) {
				return;
			}
			last_x = x;
			last_y = y;

			timer();
		});
		(window as Gtk.Widget)?.add_controller(mouse);

		var gesture = new Gtk.GestureClick ();
		gesture.pressed.connect((n) => {
			if (n == 2) {
				if (window.fullscreened)
					window.unfullscreen();
				else
					window.fullscreen();
			}
		});
		(window as Gtk.Widget)?.add_controller(gesture);

		var controller = new Gtk.EventControllerKey();
		controller.propagation_phase = Gtk.PropagationPhase.CAPTURE;
		controller.key_pressed.connect((keyval) => {
			timer();

			switch (keyval) {
				case Gdk.Key.Escape:
					window.unfullscreen();
					return true;
				case Gdk.Key.F11:
					if (window.fullscreened)
						window.unfullscreen();
					else
						window.fullscreen();
					return true;
				default:
					break;
			}
			return false;
		});
		(window as Gtk.Widget)?.add_controller(controller);
	});

	app.run();
}
