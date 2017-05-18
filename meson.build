project('twit-twat', ['c', 'vala'])

executable('twit-twat', 'twit-twat.vala',
	dependencies : [
		dependency('gtk+-3.0'),
		dependency('gstreamer-1.0', version : '>= 1.10.5'),
		dependency('gstreamer-video-1.0'),
		dependency('libsoup-2.4'),
		dependency('json-glib-1.0'),
		dependency('gdk-x11-3.0'),
	],
	install : true
)
