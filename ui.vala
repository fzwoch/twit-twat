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

const string ui = """
<interface>
	<object class="GtkApplicationWindow" id="window">
		<property name="default-width">960</property>
		<property name="default-height">540</property>
		<child type="titlebar">
			<object class="GtkHeaderBar">
				<property name="title">Twit-Twat</property>
				<property name="has-subtitle">true</property>
				<property name="show-close-button">true</property>
				<child>
					<object class="GtkButton" id="fullscreen">
						<property name="image">fullscreen-image</property>
						<property name="relief">none</property>
					</object>
				</child>
				<child>
					<object class="GtkSpinner" id="spinner"></object>
				</child>
				<child>
					<object class="GtkMenuButton">
						<property name="relief">none</property>
						<property name="direction">none</property>
						<property name="popover">popover</property>
					</object>
					<packing>
						<property name="pack-type">end</property>
					</packing>
				</child>
				<child>
					<object class="GtkVolumeButton" id="volume">
						<property name="relief">none</property>
						<property name="value">1.0</property>
						<property name="icons">audio-volume-muted-symbolic
audio-volume-high-symbolic
audio-volume-low-symbolic
audio-volume-medium-symbolic</property>
					</object>
					<packing>
						<property name="pack-type">end</property>
					</packing>
				</child>
				<child>
					<object class="GtkEntry" id="channel">
						<property name="placeholder-text">Twitch channel</property>
					</object>
					<packing>
						<property name="pack-type">end</property>
					</packing>
				</child>
			</object>
		</child>
	</object>
	<object class="GtkImage" id="fullscreen-image">
		<property name="icon-name">view-fullscreen-symbolic</property>
	</object>
	<object class="GtkPopover" id="popover">
		<child>
			<object class="GtkBox">
				<property name="visible">true</property>
				<property name="margin">10</property>
				<property name="orientation">vertical</property>
				<child>
					<object class="GtkRadioButton" id="speed">
						<property name="label">Unlimited</property>
						<property name="visible">true</property>
						<property name="active">true</property>
					</object>
				</child>
				<child>
					<object class="GtkRadioButton">
						<property name="label">1.0 Mbps</property>
						<property name="visible">true</property>
						<property name="group">speed</property>
					</object>
				</child>
				<child>
					<object class="GtkRadioButton">
						<property name="label">1.5 Mbps</property>
						<property name="visible">true</property>
						<property name="group">speed</property>
					</object>
				</child>
				<child>
					<object class="GtkRadioButton">
						<property name="label">2.0 Mbps</property>
						<property name="visible">true</property>
						<property name="group">speed</property>
					</object>
				</child>
				<child>
					<object class="GtkRadioButton">
						<property name="label">2.5 Mbps</property>
						<property name="visible">true</property>
						<property name="group">speed</property>
					</object>
				</child>
				<child>
					<object class="GtkRadioButton">
						<property name="label">3.0 Mbps</property>
						<property name="visible">true</property>
						<property name="group">speed</property>
					</object>
				</child>
				<child>
					<object class="GtkRadioButton">
						<property name="label">3.5 Mbps</property>
						<property name="visible">true</property>
						<property name="group">speed</property>
					</object>
				</child>
				<child>
					<object class="GtkRadioButton">
						<property name="label">4.0 Mbps</property>
						<property name="visible">true</property>
						<property name="group">speed</property>
					</object>
				</child>
				<child>
					<object class="GtkRadioButton">
						<property name="label">5.0 Mbps</property>
						<property name="visible">true</property>
						<property name="group">speed</property>
					</object>
				</child>
				<child>
					<object class="GtkRadioButton">
						<property name="label">6.0 Mbps</property>
						<property name="visible">true</property>
						<property name="group">speed</property>
					</object>
				</child>
			</object>
		</child>
	</object>
</interface>
""";
