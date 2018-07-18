#!/bin/sh
#
# This script reads the latest GoogleMap URL produced by pinpoint.sh on a client Mac and returns it as an extension attribute
if [ ! -e "/Library/Application Support/pinpoint/location.plist" ]; then
	exit 1
else
	url=`/usr/bin/defaults read "/Library/Application Support/pinpoint/location" GoogleMap`
	echo "<result>$url</result>"
fi
exit 0
