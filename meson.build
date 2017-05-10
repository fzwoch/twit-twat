project('twit-twat', ['c', 'vala'])

deps = []

deps += dependency('gtk+-3.0')
deps += dependency('gstreamer-1.0', version : '>= 1.10.5')
deps += dependency('gstreamer-video-1.0')
deps += dependency('libsoup-2.4')
deps += dependency('json-glib-1.0')
deps += dependency('x11')
deps += dependency('gdk-x11-3.0')

executable('twit-twat', 'twit-twat.vala',
	dependencies : deps,
	install : true
)
