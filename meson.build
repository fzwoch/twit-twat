project('twit-twat', 'c', 'vala')

twit_twat_args = []
x11_dep = dependency('x11', required : false)
if x11_dep.found()
	twit_twat_args = ['-D', 'HAVE_X11']
endif

executable('twit-twat', 'twit-twat.vala',
	dependencies : [
		dependency('gtk+-3.0'),
		dependency('gstreamer-1.0', version : '>= 1.10.5'),
		dependency('libsoup-2.4'),
		dependency('json-glib-1.0'),
		x11_dep
	],
	vala_args : twit_twat_args,
	install : true
)

install_data('twit-twat.desktop', install_dir : 'share/applications')
install_data('twit-twat.png', install_dir : 'share/twit-twat')
