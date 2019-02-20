#!/bin/sh
# pinpoint post install script
/usr/sbin/chown -R root:wheel "/Library/Application Support/pinpoint"
/bin/chmod 755 "/Library/Application Support/pinpoint/bin/pinpoint.sh"
/usr/sbin/chown root:wheel "/Library/LaunchDaemons/com.jelockwood.pinpoint.plist"
if [ ! -f "/Library/Preferences/com.jelockwood.pinpoint.plist" ]; then
	/usr/bin/defaults write "/Library/Preferences/com.jelockwood.pinpoint" USE_ALTITUDE -bool FALSE
	/usr/bin/defaults write "/Library/Preferences/com.jelockwood.pinpoint" USE_GEOCODE -bool TRUE
	/usr/bin/defaults write "/Library/Preferences/com.jelockwood.pinpoint" YOUR_API_KEY -string ""
else
	use_geocode=`/usr/bin/defaults read "/Library/Preferences/com.jelockwood.pinpoint" USE_GEOCODE`
	if [ -z "$use_geocode" ]; then
        	/usr/bin/defaults write "/Library/Preferences/com.jelockwood.pinpoint" USE_GEOCODE -bool TRUE
	fi
	use_altitude=`/usr/bin/defaults read "/Library/Preferences/com.jelockwood.pinpoint" USE_ALTITUDE`
	if [ -z "$use_altitude" ]; then
        	/usr/bin/defaults write "/Library/Preferences/com.jelockwood.pinpoint" USE_ALTITUDE -bool FALSE
	fi
	your_api_key=`/usr/bin/defaults read "/Library/Preferences/com.jelockwood.pinpoint" YOUR_API_KEY`
	if [ -z "$your_api_key" ]; then
        	/usr/bin/defaults write "/Library/Preferences/com.jelockwood.pinpoint" YOUR_API_KEY -string ""
	fi
fi
/bin/launchctl load "/Library/LaunchDaemons/com.jelockwood.pinpoint.plist"
exit