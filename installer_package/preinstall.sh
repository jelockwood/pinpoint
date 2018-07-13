!#/bin/sh
# pinpoint 3.x pre-install script
# Removes any previous copy
if [ -f "/Library/LaunchDaemons/com.clburlison.pinpoint.plist" ]; then
	/bin/launchctl unload "/Library/LaunchDaemons/com.clburlison.pinpoint"
	/bin/rm "/Library/LaunchDaemons/com/clburlison.pinpoint.plist"
fi
if [ -d "/Library/Application Support/pinpoint" ]; then
	/bin/rm -r "/Library/Application Support/pinpoint"
fi
exit