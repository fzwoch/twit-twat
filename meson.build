project('twit-twat', 'c', 'vala')

executable('twit-twat', 'twit-twat.vala',
	dependencies : [
		dependency('gtk+-3.0'),
		dependency('gstreamer-1.0', version : '>= 1.10.5'),
		dependency('libsoup-2.4'),
		dependency('json-glib-1.0'),
		dependency('x11')
	],
	install : true
)

install_data('twit-twat.desktop', install_dir : 'share/applications')
install_data('twit-twat.png', install_dir : 'share/twit-twat')
