#!/bin/bash

####################################################################################################
# DESC:  When the script runs, it will make a copy of the existing location services
#	/var/db/locationd/client.plist to be used in case a revert is needed. Following, we swap 0's
#	to 1's within the client.plist for Teams and Teams helper to enable them. 
# REFS:   N/A
#
# Author: Bill Addis
#
# HISTORY
#	- v.0.0: discovery of appropriate directories and files for manipulation
#	- v.1.0:  initial script upload
#	- v.1.1:	added additional logging, as well as error checking to ensure the plist exists before manipulation
#	- v.1.1:	discovered+fixed a bug where if an end-user manually DISABLES Teams from using location services, the "authorized key" disappears and cannot be set
#	- v.1.2: Adding an initial check at the top to see if location services for MacOS are enabled
#	- v.1.3: Updated to account for changes in macOS Ventura
#	- v.1.5 Bill Addis, Sep 15, 2023: Added for loop to update all Teams location entries (old Teams and new)
#   - v.1.6 Bill Addis, Oct 23, 2023: Added support for Sonoma. Updated script to loop for all Teams versions
#	- v.1.7: Julian Ortega, Dec 20, 2023: Updated to work for generic apps instead of MS Teams
####################################################################################################
# This version modified to instead default to granting Python permission
scriptVersion="2023.12.2"
scriptLog="${4:-"/var/log/com.jamf.appLocationServices.log"}"
appName="${5:-"Python"}"
appIdentifier="${6:-"org.python.python"}"

function updateScriptLog() {
    echo -e "$( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

updateScriptLog "SCRIPT VERSION: $scriptVersion"

if [[ ! -f "${scriptLog}" ]]; then
    touch "${scriptLog}"
fi

# Set line debugging
PS4='Line ${LINENO}: '

# updateScriptLog mount point in Jamf
updateScriptLog $1

# Is location services enabled? 
location_enabled=$(sudo -u "_locationd" defaults -currentHost read "/var/db/locationd/Library/Preferences/ByHost/com.apple.locationd" LocationServicesEnabled)
if [[ "$location_enabled" = "1" ]]; then
	updateScriptLog "Location Services are enabled, moving on..."
else
	updateScriptLog "Location Services disabled. Enabling them..."
# UPDATE THIS LINE TO ACTUALLY ENABLE LOCATION SERVICES
    jamf policy -event location
    sleep 3
	location_enabled=$(sudo -u "_locationd" defaults -currentHost read "/var/db/locationd/Library/Preferences/ByHost/com.apple.locationd" LocationServicesEnabled)
    if [[ "$location_enabled" = "0" ]]; then
    	updateScriptLog "Unable to enable location services...exiting"
        exit 1
    fi
fi

# Does the clients.plist exist?
updateScriptLog "Current contents of /var/db/locationd directory:"
updateScriptLog "$(ls /var/db/locationd)"

osVers=$(sw_vers -productVersion)
updateScriptLog "macOS $osVers currently installed."

if [[ "$osVers" == *13* ]] ; then
updateScriptLog "Executing for macOS Ventura..."
clients="/var/db/locationd/clients.plist"
    if [[ -f "$clients" ]]; then
        key1=$(/usr/libexec/PlistBuddy -c "Print" /var/db/locationd/clients.plist | grep :$appIdentifier | awk -F '=Dict{' '{gsub(/ /,"");gsub(":","\\:");print $1}' | head -1)
        updateScriptLog "$clients already exists! Moving on..."
        updateScriptLog "Current key values for $appName app"
        updateScriptLog "$(/usr/libexec/PlistBuddy -c "Print $key1" $clients)"
        updateScriptLog "================================="

        # Create a backup of the existing client location services file
        cp $clients /var/db/locationd/clients.BAK

        # Create an extra working backup
        cp $clients /private/var/tmp/

        # Convert our working backup client plist to xml for editing
        plutil -convert xml1 /private/var/tmp/clients.plist

        count=1

        for i in $(/usr/libexec/PlistBuddy -c "Print" /private/var/tmp/clients.plist | grep :$appIdentifier | awk -F '=Dict{' '{gsub(/ /,"");gsub(":","\\:");print $1}');

            do
            updateScriptLog "Current key value for key$count:"
            updateScriptLog "$(/usr/libexec/PlistBuddy -c "Print $i" $clients)"

            # Use Plist Buddy to mark-up client plist, enabling app's location services
            /usr/LibExec/PlistBuddy -c "Set :$i:Authorized true" /private/var/tmp/clients.plist
            # Check return for last command
            if [[ "$?" = "1" ]]; then
                updateScriptLog "Authorized key seems to be missing...re-adding the key"
                /usr/LibExec/PlistBuddy -c "Add :$i:Authorized bool true" /private/var/tmp/clients.plist
                updateScriptLog "Adding 'authorized' key for $i location services returned: $?"
            fi
            updateScriptLog "Setting $i location services returned: $?"

            ((count=count+1))
            done

        # Convert back to binary
        plutil -convert binary1 /private/var/tmp/clients.plist

        # Put the updated client plist into appropriate dir
        cp /private/var/tmp/clients.plist $clients

        # Kill and restart the location services daemon and remove our temp file
        killall locationd
        rm /private/var/tmp/clients.plist
    else
        updateScriptLog "$clients does not exist...exiting"
        exit 1
    fi
elif [[ "$osVers" == *12* ]] ; then
    updateScriptLog "Executing for macOS 12 or less..."
    clients="/var/db/locationd/clients.plist"
    if [[ -f "$clients" ]]; then
        updateScriptLog "$clients already exists! Moving on..."
        updateScriptLog "Current key values for $appName app:"
        updateScriptLog "$(/usr/libexec/PlistBuddy -c "Print :$appIdentifier" $clients)"
        updateScriptLog "================================="

        # Create a backup of the existing client location services file
        cp $clients /var/db/locationd/clients.BAK

        # Create an extra working backup
        cp $clients /private/var/tmp/

        # Convert our working backup client plist to xml for editing
        plutil -convert xml1 /private/var/tmp/clients.plist

        # Use Plist Buddy to mark-up client plist, enabling app's location services
        /usr/LibExec/PlistBuddy -c "Set :com.$appIdentifier:Authorized true" /private/var/tmp/clients.plist
        # Check return for last command
        if [[ "$?" = "1" ]]; then
            updateScriptLog "Authorized key seems to be missing...re-adding the key"
            /usr/LibExec/PlistBuddy -c "Add :$appIdentifier:Authorized bool true" /private/var/tmp/clients.plist
            updateScriptLog "Adding 'authorized' key for $appName app location services returned: $?"
            #/usr/LibExec/PlistBuddy -c "Set :$appIdentifier:Authorized true" /private/var/tmp/clients.plist
        fi
        updateScriptLog "Setting $appName app location services returned: $?"

        # Convert back to binary
        plutil -convert binary1 /private/var/tmp/clients.plist

        # Put the updated client plist into appropriate dir
        cp /private/var/tmp/clients.plist $clients

        # Kill and restart the location services daemon and remove our temp file
        killall locationd
        rm /private/var/tmp/clients.plist
    else
        updateScriptLog "$clients does not exist...exiting"
        exit 1
    fi
elif [[ "$osVers" == *14* ]] ; then
    updateScriptLog "Executing for macOS 14 Sonoma..."
    clients="/var/db/locationd/clients.plist"
        if [[ -f "$clients" ]]; then
            updateScriptLog "$clients already exists! Moving on..."

            # Create a backup of the existing client location services file
            cp $clients /var/db/locationd/clients.BAK

            # Create an extra working backup
            cp $clients /private/var/tmp/

            # Convert our working backup client plist to xml for editing
            plutil -convert xml1 /private/var/tmp/clients.plist

            count=1

            for i in $(/usr/libexec/PlistBuddy -c "Print" /private/var/tmp/clients.plist | grep -a :i$appIdentifier | awk -F '=Dict{' '{gsub(/ /,"");gsub(":","\\:");print $1}'  | sed "s/..$//");

            do
            updateScriptLog "Current key value for key$count:"
            updateScriptLog "$(/usr/libexec/PlistBuddy -c "Print $i" $clients)"

            # Use Plist Buddy to mark-up client plist, enabling app's location services
            /usr/LibExec/PlistBuddy -c "Set :$i\::Authorized true" /private/var/tmp/clients.plist
            # Check return for last command
            if [[ "$?" = "1" ]]; then
                updateScriptLog "Authorized key seems to be missing...re-adding the key"
                /usr/LibExec/PlistBuddy -c "Add :$i\::Authorized bool true" /private/var/tmp/clients.plist
                updateScriptLog "Adding 'authorized' key for $i location services returned: $?"
            fi
            updateScriptLog "Setting $i location services returned: $?"

            ((count=count+1))
            done

            # Convert back to binary
            plutil -convert binary1 /private/var/tmp/clients.plist

            # Put the updated client plist into appropriate dir
            cp /private/var/tmp/clients.plist $clients

            # Kill and restart the location services daemon and remove our temp file
            killall locationd
            #rm /private/var/tmp/clients.plist
        else
            updateScriptLog "$clients does not exist...exiting"
            exit 1
        fi
fi
# Display the final return code 
exit $?
