project('twit-twat', ['c', 'vala'])

gtk = dependency('gtk+-3.0')
gst = dependency('gstreamer-1.0', version : '>= 1.10.0')
soup = dependency('libsoup-2.4')
json = dependency('json-glib-1.0')

executable('twit-twat', 'twit-twat.vala',
	dependencies : [gtk, gst, soup, json]
)
