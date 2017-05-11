Twit-Twat
=========

An experiment to receive Twitch.tv streams on Linux with the least possible amount of CPU overhead. Specifically, make use if GStreamer's support of VAAPI plugins.

Note that if VAAPI is not available or not correctly installed, it falls back to less efficient playback silently.

NVIDIA
------

If you use the NVIDIA proprietary driver you need to install the VDPAU <-> VAAPI bridge as NVIDIA does not directly support VAAPI:

```bash
$ sudo apt install vdpau-va-driver
```

Also, this driver is not actively maintained and does not support all VAAPI features. Therefore it is not white listed in GStreamers's VAAPI support.

For actually getting VAAPI working you also need to have the following environment variable set:

```bash
$ export GST_VAAPI_ALL_DRIVERS=1
```
