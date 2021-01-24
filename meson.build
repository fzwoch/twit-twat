project('twit-twat', 'c', 'vala')

gen = generator(find_program('glib-compile-resources'),
	output : '@BASENAME@.c',
	arguments : ['--target=@OUTPUT@', '--generate-source',
		'--sourcedir=' + meson.current_source_dir(), '@INPUT@'
	]
)

executable('twit-twat', 'twit-twat.vala',
	gen.process('resources.xml'),
	dependencies : [
		dependency('gtk+-3.0'),
		dependency('gstreamer-1.0'),
		dependency('libsoup-2.4'),
		dependency('json-glib-1.0'),
		dependency('x11'),
	],
	install : true,
)

data = configuration_data()
data.set('prefix', get_option('prefix'))

desktop_file = configure_file(
	input : 'twit-twat.desktop.in',
	output : 'twit-twat.desktop',
	configuration : data,
)

install_data(desktop_file, install_dir : 'share/applications')
install_data('twit-twat.png', install_dir : 'share/twit-twat')
