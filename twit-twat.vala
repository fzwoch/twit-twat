//
// Twit-Twat
//
// Copyright (C) 2017-2023 Florian Zwoch <fzwoch@gmail.com>
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

int main (string[] args) {
	Gst.init(ref args);

	var app = new Gtk.Application(
		"zwoch.florian.twit-twat",
		ApplicationFlags.FLAGS_NONE
	);

	app.activate.connect(() => {
		var builder = new Gtk.Builder.from_string(ui, -1);

		var window = builder.get_object("window") as Gtk.ApplicationWindow;
		app.add_window(window);
		window.show_all();

		var controller = new Gtk.EventControllerKey(window);
		controller.key_pressed.connect((keyval) => {
			switch (keyval) {
				case Gdk.Key.Escape:
					window.unfullscreen();
					return true;
				case Gdk.Key.F11:
					if ((window.get_window().get_state() & Gdk.WindowState.FULLSCREEN) != 0)
						window.unfullscreen();
					else
						window.fullscreen();
					return true;
				default:
					break;
			}
			return false;
		});
		controller.ref(); //leak?

		var fullscreen = builder.get_object("fullscreen") as Gtk.Button;
		fullscreen.button_press_event.connect(() => {
			window.fullscreen();
			return true;
		});

		Gst.Bin pipeline = null;

		var volume = builder.get_object("volume") as Gtk.VolumeButton;
		volume.value_changed.connect(() => {
			if (pipeline != null) {
				var vol = pipeline.get_by_name("volume") as dynamic Gst.Element;
				vol.volume = volume.adjustment.value;
			}
		});

		var channel = builder.get_object("channel") as Gtk.Entry;
		channel.activate.connect(() => {
			channel.sensitive = false;
			try {
				var p = new Subprocess(SubprocessFlags.STDOUT_PIPE , "streamlink", "--json", "--stream-url", "twitch.tv/" + channel.text.strip().down(), "best");
				p.wait_check_async.begin(null, (obj, res) => {
					var buffer = new uint8[8192];
					try {
						p.get_stdout_pipe().read(buffer);
					} catch (IOError e) {
						warning(e.message);
					}

					var parser = new Json.Parser();
					try {
						parser.load_from_data((string) buffer);
					} catch (Error e) {
						warning(e.message);
					}

					if (parser.get_root().get_object().has_member("error")) {
						var dialog = new Gtk.MessageDialog(window, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, "No channel");
						dialog.run();
						dialog.destroy();

						channel.sensitive = true;
						window.set_focus(channel);
						return;
					}

					var header_bar = window.get_titlebar() as Gtk.HeaderBar;
					header_bar.subtitle = parser.get_root().get_object().get_object_member("metadata").get_string_member("author");

					if (pipeline != null) {
						pipeline.set_state(Gst.State.NULL);
						pipeline.get_bus().remove_watch();

						var sink = pipeline.get_by_name("sink") as dynamic Gst.Element;
						window.remove(sink.widget);
					}

					try {
						pipeline = Gst.parse_launch("uridecodebin3 name=decodebin caps=video/x-h264;audio/x-raw ! h264parse ! vah264dec qos=false ! vapostproc ! gtkwaylandsink name=sink decodebin. ! audioconvert ! pulsesink name=volume") as Gst.Bin;
					} catch (Error e) {
						warning(e.message);
					}

					pipeline.get_bus().add_watch(Priority.DEFAULT, (bus, message) => {
						switch (message.type) {
							case Gst.MessageType.EOS:
								pipeline.set_state(Gst.State.READY);
								var dialog = new Gtk.MessageDialog(window, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.INFO, Gtk.ButtonsType.CLOSE, "Broadcast finished");
								dialog.run();
								dialog.destroy();
								break;
							case Gst.MessageType.WARNING:
								Error err;
								message.parse_warning(out err, null);
								warning(err.message);
								break;
							case Gst.MessageType.ERROR:
								Error err;
								pipeline.set_state(Gst.State.READY);
								message.parse_error(out err, null);
								var dialog = new Gtk.MessageDialog(window, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, err.message);
								dialog.run();
								dialog.destroy();
								break;
							case Gst.MessageType.BUFFERING:
								int percent;
								message.parse_buffering(out percent);

								var spinner = builder.get_object("spinner") as Gtk.Spinner;
								spinner.active = percent < 100 ? true : false;
								break;
							default:
								break;
						}
						return true;
					});

					var sink = pipeline.get_by_name("sink") as dynamic Gst.Element;
					Gtk.Widget widget = sink.widget;

					window.add(widget);
					window.show_all();

					widget.button_press_event.connect((event) => {
						switch (event.type) {
							case Gdk.EventType.DOUBLE_BUTTON_PRESS:
								if ((window.get_window().get_state() & Gdk.WindowState.FULLSCREEN) != 0)
									window.unfullscreen();
								else
									window.fullscreen();
								return true;
							default:
								break;
						}
						return false;
					});

					var decodebin = pipeline.get_by_name("decodebin") as dynamic Gst.Element;
					decodebin.uri = parser.get_root().get_object().get_string_member("master").replace("allow_audio_only=true", "allow_audio_only=false");
					decodebin.use_buffering = true;

					var vol = pipeline.get_by_name("volume") as dynamic Gst.Element;
					vol.volume = volume.adjustment.value;

					var radio = builder.get_object("speed") as Gtk.RadioButton;
					radio.get_group().foreach ((b) => {
						if (b.active) {
							float speed = 0.0f;
							b.label.scanf("%f Mbps", &speed);
							decodebin.connection_speed = (int)(speed * 1000);
						}
					});

					pipeline.set_state(Gst.State.PLAYING);

					channel.text = "";
					channel.sensitive = true;

					window.set_focus(null);
				});
			} catch (Error e) {
				warning(e.message);
			}
		});
		window.set_focus(channel);

		window.delete_event.connect (() => {
			if (pipeline != null) {
				pipeline.set_state(Gst.State.NULL);
				pipeline.get_bus().remove_watch();

				var sink = pipeline.get_by_name("sink") as dynamic Gst.Element;
				window.remove(sink.widget);
			}
			return false;
		});
	});

	return app.run(args);
}
