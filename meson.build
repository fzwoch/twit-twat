#
# Twit-Twat
#
# Copyright (C) 2017-2023 Florian Zwoch <fzwoch@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

project('twit-twat', 'vala')

resources = custom_target('resources.c',
	input : 'resources.xml',
	output : '@BASENAME@.c',
	command : [
		find_program('glib-compile-resources'),
		'--target=@OUTPUT@', '--generate-source',
		'--sourcedir=' + meson.current_source_dir(), '@INPUT@',
	],
	build_always_stale : true,
)

executable('twit-twat', 'twit-twat.vala',
	resources,
	dependencies : [
		dependency('gtk+-3.0'),
		dependency('gstreamer-1.0'),
		dependency('json-glib-1.0'),
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
