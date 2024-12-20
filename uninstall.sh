#!/bin/sh

# Script to remove all parts of Pinpoint

if [ -e "/Library/LaunchDaemons/com.jelockwood.pinpoint.plist" ]; then
  /bin/launchctl unload -w "/Library/LaunchDaemons/com.jelockwood.pinpoint.plist"
  /bin/rm -rf "/Library/LaunchDaemons/com.jelockwood.pinpoint.list"
fi

if [ -e "/Library/Preferences/com.jelockwood.pinpoint.plist" ]; then
  /bin/rm -rf "/Library/Preferences/com.jelockwood.pinpoint.plist"
fi

if [ -d "/Library/Application Support/pinpoint" ]; then
  /bin/rm -rf "/Library/Application Support/pinpoint"
fi

/usr/sbin/pkgutil --forget com.jelockwood.pinpoint.pkg

exit
