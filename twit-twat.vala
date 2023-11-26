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

	var app = new Gtk.Application(null, ApplicationFlags.FLAGS_NONE);

	app.activate.connect(() => {
		var builder = new Gtk.Builder.from_resource ("/twit-twat/twit-twat.ui");

		var window = builder.get_object("window") as Gtk.ApplicationWindow;
		app.add_window(window);
		window.present();

		var box = builder.get_object("speed") as Gtk.ListBox;
		box.select_row(box.get_row_at_index(7));

		Gst.Bin pipeline = null;

		var controller = new Gtk.EventControllerKey();
		controller.key_pressed.connect((keyval) => {
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

		var fullscreen = builder.get_object("fullscreen") as Gtk.Button;
		fullscreen.clicked.connect(() => {
			window.fullscreen();
		});

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
				var p = new Subprocess(SubprocessFlags.STDOUT_PIPE , "streamlink", "--json", "--stream-url", (channel.text.strip().down().has_prefix("@") ? "youtube.com/" : "twitch.tv/") + channel.text.strip().down(), "best");
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
						var dialog = new Gtk.AlertDialog("No channel");
						dialog.show(window);
						channel.sensitive = true;
						channel.grab_focus();
						return;
					}

					var subtitle = builder.get_object("subtitle") as Gtk.Label;
					subtitle.label = parser.get_root().get_object().get_object_member("metadata").get_string_member("author");

					var spinner = builder.get_object("spinner") as Gtk.Spinner;

					if (pipeline != null) {
						pipeline.set_state(Gst.State.NULL);
						pipeline.get_bus().remove_watch();
					}

					try {
						pipeline = Gst.parse_launch("uridecodebin3 name=decodebin caps=video/x-h264;audio/x-raw ! h264parse ! vah264dec qos=false ! glsinkbin sink=\"gtk4paintablesink name=sink\" decodebin. ! audioconvert ! volume name=volume ! pulsesink") as Gst.Bin;
					} catch (Error e) {
						warning(e.message);
					}

					pipeline.get_bus().add_watch(Priority.DEFAULT, (bus, message) => {
						switch (message.type) {
							case Gst.MessageType.STATE_CHANGED:
								if (message.src != pipeline)
									break;
								Gst.State state, oldstate;
								message.parse_state_changed(out oldstate, out state, null);
								if (oldstate == Gst.State.PAUSED && state == Gst.State.READY)
									spinner.spinning = false;
								break;
							case Gst.MessageType.EOS:
								pipeline.set_state(Gst.State.READY);
								var dialog = new Gtk.AlertDialog("Broadcast finished");
								dialog.show(window);
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
								var dialog = new Gtk.AlertDialog(err.message);
								dialog.show(window);
								break;
							case Gst.MessageType.BUFFERING:
								int percent;
								message.parse_buffering(out percent);

								if (!spinner.spinning && percent < 100)
									pipeline.set_state(Gst.State.PAUSED);
								else if (spinner.spinning && percent == 100)
									pipeline.set_state(Gst.State.PLAYING);

								spinner.spinning = percent < 100 ? true : false;
								break;
							default:
								break;
						}
						return true;
					});

					var sink = pipeline.get_by_name("sink") as dynamic Gst.Element;
					Gdk.Paintable paintable = sink.paintable;

					var picture = builder.get_object("picture") as Gtk.Picture;
					picture.paintable = paintable;

					var gesture = new Gtk.GestureClick ();
					gesture.pressed.connect((n) => {
						if (n == 2) {
							if (window.fullscreened)
								window.unfullscreen();
							else
								window.fullscreen();
						}
					});
					picture.add_controller(gesture);

					var decodebin = pipeline.get_by_name("decodebin") as dynamic Gst.Element;
					decodebin.uri = parser.get_root().get_object().get_string_member("master").replace("allow_audio_only=true", "allow_audio_only=false");

					var vol = pipeline.get_by_name("volume") as dynamic Gst.Element;
					vol.volume = volume.adjustment.value;

					var r = box.get_selected_row() as Gtk.ListBoxRow;
					float speed = 0.0f;
					(r.get_child() as Gtk.Label)?.label.scanf("%f Mbps", &speed);
					decodebin.connection_speed = (int)(speed * 1000);

					pipeline.set_state(Gst.State.PLAYING);

					channel.text = "";
					channel.sensitive = true;

					window.set_focus(null);
				});
			} catch (Error e) {
				warning(e.message);
			}
		});
		channel.grab_focus();

		window.close_request.connect (() => {
			if (pipeline != null) {
				pipeline.set_state(Gst.State.NULL);
				pipeline.get_bus().remove_watch();
			}
			return false;
		});
	});

	return app.run(args);
}
