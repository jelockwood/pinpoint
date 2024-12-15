#!/bin/bash
# Copyright John E. Lockwood (2018-2024)
# Modified by Alex Narvey, Precursor.ca while waiting for version 3.3 or higer.
# pinpoint a script to find your Mac's location
#
# see https://github.com/jelockwood/pinpoint
#
# Written to not use Location Services under macOS 14.3.1 or earlier. Unfortunately changes in
# macOS Sonoma 14.4 have now made it a necessity to use Location Services.
#
# Version 3.0 added a new feature contributed by Ofir Gal. This optional feature analyses 
# the SSID list and compares it to the previous list to see if this indicates a big
# enough change in location to justify calling the Google APIs again.
#
# The aim is to reduce the usage of the Google API calls and thereby either keep you within
# the free allowance or at least reduce the cost.
#
# Many thanks are therefore given to Ofir Gal for this significant enhancement.
#
# Script name
scriptname=$(basename -- "$0")
# Version number
versionstring="3.4.0b"
# Feature added by Alex Narvey so that if currently connected to a known SSID the script will except without
# calling Google APIs as the presumption is made that the location is then already known. This is to further
# reduce the quantity of Google API calls and keep costs down. If The URL defined is invalid and the CURL
# fails then this does not operate and the script runs as normal
#
# Google have further changed the costs for using their APIs and this option can help keep your usage down
# to a level that is still within their 'free' limit
# 
# The webpage being access via the URL is a plain text file with one SSID name per line
#
# Define Known Networks list for exemptions below (the name of each Wifi network on a separate line of a .txt file served from a web server)
KNOWNNETWORKS="https://example.com/SSID.txt"
# get date and time in UTC hence timezone offset is zero
rundate=`date -u +%Y-%m-%d\ %H:%M:%S\ +0000`
#echo "$rundate"
#
# help information
usage()
{
    echo "usage: $scriptname [-V] [-j] [-h] [-g] [-a] [-k yourkeyhere] [-d] [-o]
	-V | --version		Print script version and exit
	-j | --jamf		Return map URL only to stdout formatted as an
    				extension attribute for use with JAMF Pro
	-h | --help		show this help message and exit
	-g | --geocode		Use Geocode API to look up street address
	-a | --altitude		Use Elevation API to look up altitude
	-k | --key yourkeyhere	Specify your Google API key
	-d | --debug		Log debug information
	-o | --optim		Use optmisation to minimise Google API calls"
}

#debugLog="/var/log/pinpoint.log"
debugLog="/Library/Application Support/pinpoint/bin/pinpoint.log"

function DebugLog {
	if [[ "${use_debug}" == "True" ]] || [[ "${use_debug}" == "true" ]] ; then
		echo "$1" >> "$debugLog"
		echo "$1"
	fi
}

# fuzzy string comparison 
function levenshtein {
    if [ "$#" -ne "2" ]; then
        echo "Usage: $0 word1 word2" >&2
    elif [ "${#1}" -lt "${#2}" ]; then
        levenshtein "$2" "$1"
    else
        local str1len=$((${#1}))
        local str2len=$((${#2}))
        local d i j
        for i in $(seq 0 $(((str1len+1)*(str2len+1)))); do
            d[i]=0
        done
        for i in $(seq 0 $((str1len))); do
            d[$((i+0*str1len))]=$i
        done
        for j in $(seq 0 $((str2len))); do
            d[$((0+j*(str1len+1)))]=$j
        done

        for j in $(seq 1 $((str2len))); do
            for i in $(seq 1 $((str1len))); do
                [ "${1:i-1:1}" = "${2:j-1:1}" ] && local cost=0 || local cost=1
                local del=$((d[(i-1)+str1len*j]+1))
                local ins=$((d[i+str1len*(j-1)]+1))
                local alt=$((d[(i-1)+str1len*(j-1)]+cost))
                d[i+str1len*j]=$(echo -e "$del\n$ins\n$alt" | sort -n | head -1)
            done
        done
        echo ${d[str1len+str1len*(str2len)]}
    fi
}

# Checking System Requirements
#
# macOS Sonoma 14.4 or later requires using a Python script to replace Apple's 
# airport binary. In order to run the script we require a Python runtime to be installed
# with CoreWLAN support and the script in order to obtain the needed information also 
# requires Location Services access to be enabled for the Python runtime
#
# Get macOS Version
# Improved logic for version checking submitted by Ofir Gal
installed_vers=$(sw_vers -productVersion | awk -F '.' '{printf "%d%02d%02d\n", $1, $2, $3}')
#
# If macOS version is 14.4 or higher we need to do additional checks
if (( installed_vers >= 140400 )); then
# Check MacAdmins Python3 is installed
        if [ ! -e "/usr/local/bin/managed_python3" ]; then
                echo "No Python"
#               DebugLog "running macOS 14.4 or later but required Python is not installed"
                exit 1
        else
# MacAdmins Python3 is installed, now check pinpoint_scan.py is installed
                if [ ! -e "/Library/Application Support/pinpoint/bin/pinpoint_scan.py" ]; then
                        echo "pinpoint_scan.py not found"
#                       DebugLog "pinpoint_scan.py not found"
                        exit 1
                fi
                echo "Python"
        fi
#       DebugLog "incompatible macOS"
#       exit 1
fi

# Set your Google geolocation API key here
# You can get an API key here https://developers.google.com/maps/documentation/geolocation/get-api-key
#
# Set API key in script - mainly for use with JAMF
YOUR_API_KEY="pasteyourkeyhere"
#
# Set initial default preference values
use_geocode="True"
use_altitude="False"
use_optim="False"
use_debug="False"
jamf=0
commandoptions=0
#
# killall cfprefsd
# For normal non-jamf use read preference file for API key
# First check for any command line options

# Check parameters
while [ "$1" != "" ]; do
    case $1 in
		-V | --version )        	echo "$scriptname version = $versionstring"
        					exit
                                		;;
		-j | --jamf )    		jamf=1
						commandoptions=1
                                		;;
		-a | --altitude )		use_altitude=1
						commandoptions=1
						;;
		-g | --geocode )		use_geocode=1
						commandoptions=1
						;;
		-d | --debug )			use_debug="True"
						commandoptions=1
						echo "$scriptname Debug = $use_debug"
						;;
		-o | --optim )			use_optim="True"
						commandoptions=1
						;;
		-k | --key )			YOUR_API_KEY="$2"
						commandoptions=1
						shift
						;;
		-h | --help )           	usage
                                		exit
                                		;;
		* )                     	usage
                                		exit 1
						;;
    esac
    shift
done

# Second if no command line options check preference file
if [ $commandoptions -eq 0 ]; then
	readonly DOMAIN="com.jelockwood.pinpoint"
	# Use CFPreferences no defaults command as it supports both local, managed and config profiles automatically
	pref_value() {
		osascript -l JavaScript -e "ObjC.import('Foundation'); ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('$1').objectForKey('$2'))"
	}

	use_geocode=$(pref_value ${DOMAIN} "USE_GEOCODE")
	use_altitude=$(pref_value ${DOMAIN} "USE_ALTITUDE")
	use_debug=$(pref_value ${DOMAIN} "DEBUG")
	use_optim=$(pref_value ${DOMAIN} "OPTIMISE")
	PREFERENCE_API_KEY=$(pref_value ${DOMAIN} "YOUR_API_KEY")
	if [ ! -z "$PREFERENCE_API_KEY" ]; then
		YOUR_API_KEY="$PREFERENCE_API_KEY"
	fi
	PREFERENCE_KNOWN_NETWORKS_URL=$(pref_value ${DOMAIN} "KNOWN_NETWORKS_URL")
	if [ ! -z "$PREFERENCE_KNOWN_NETWORKS_URL" ]; then
		KNOWNNETWORKS="$PREFERENCE_KNOWN_NETWORKS_URL"
	fi
fi
#
# Validate YOUR_API_KEY
# If not valid from built-in, command-line or preference file via all of above then exit with error
if [ "$YOUR_API_KEY" == "pasteyourkeyhere" ] || [ "$YOUR_API_KEY" == "yourkeyhere" ] || [ -z "$YOUR_API_KEY" ]; then
	DebugLog "Invalid Google API key"
	exit 1
fi
#

#
# Location of plist with results
resultslocation="/Library/Application Support/pinpoint/location.plist"
#

#
# Get list of network interfaces, find WiFi interface
# Get status of WiFi interface i.e. whether it is already turned on
# If off turn it on as it is needed to get the list of BSSIDs in your location
# It is not necessary to actually connect to any WiFi network
DebugLog ""
DebugLog "### pinpoint $versionstring run ###"
DebugLog "$(date)"

INTERFACE=$(networksetup -listallhardwareports | grep -A1 Wi-Fi | tail -1 | awk '{print $2}')
STATUS=$(networksetup -getairportpower $INTERFACE | awk '{print $4}')
if [ $STATUS = "Off" ] ; then
    networksetup -setairportpower $INTERFACE on
    sleep 5
fi
#

# Run as user logic for Python script
currentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')

runAsUser() {
    if [[ $currentUser != "loginwindow" ]]; then
        uid=$(id -u "$currentUser")
        launchctl asuser $uid sudo -u $currentUser "$@"
    fi
}
# End Run as user logic for Python Script

# Run the Python scan script as the user and not root

if (( installed_vers >= 140400 )); then
# If macOS newer than 14.4 then use Python script to get list of SSIDs
    if gl_ssids="$(runAsUser '/Library/Application Support/pinpoint/bin/pinpoint_scan.py'  | tail -n +2 | awk '{print substr($0, 34, 17)"$"substr($0, 52, 4)"$"substr($0, 1, 32)"$"substr($0, 57, 3)}' | sort -t $ -k2,2rn | head -12 2>&1)"; then
        rc=0
        stdout="$gl_ssids"
    else
# Likely error is caused by Location Services not yet enabled for Python, script needs to be
# run at least once first to trigger a request in Privacy & Security which can then be approved.
# See - https://github.com/jelockwood/pinpoint/wiki/Enabling-Location-Services
        rc=$?
        stderr="$gl_ssids"
	DebugLog "$stderr"
	exit 1
    fi
else
# If macOS older than 14.4 use built-in Apple tool to get list of SSIDs
    gl_ssids=`/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport -s | tail -n +2 | awk '{print substr($0, 34, 17)"$"substr($0, 52, 4)"$"substr($0, 1, 32)"$"substr($0, 57, 3)}' | sort -t $ -k2,2rn | head -12`
fi
#
# We have finished using the WiFi if it was originally off we now turn it back off
if [ $STATUS = "Off" ] ; then
    networksetup -setairportpower $INTERFACE off
fi

if [[ -z "${gl_ssids}" ]]; then
	DebugLog "WiFi scan cmd failed"
	exit 1
fi


# Even though this version of pinpoint has been deliberately written not to use Location Services at all
# we check to see if Location services is or is not enabled and report this.
# This is done in order to be backwards compatible with the previous Location Services based version of pinpoint
ls_enabled=`defaults read "/var/db/locationd/Library/Preferences/ByHost/com.apple.locationd" LocationServicesEnabled`
if [ "$ls_enabled" == "1" ]; then
	defaults write "$resultslocation" LS_Enabled -int 1
	DebugLog "Location services: Enabled"
else
	defaults write "$resultslocation" LS_Enabled -int 0
	DebugLog "Location services: Disabled"
fi

# BEGIN known office exemption
# Get the Current WiFi Network Name
SSID=$(system_profiler SPAirPortDataType | awk '/Current Network Information:/ { getline; print substr($0, 13, (length($0) - 13)); exit }')
# Get the list of Office Networks
SSIDLIST=$(curl -s $KNOWNNETWORKS)
# Check against the list and exit if the SiFi is set to a known office network
if printf '%s\0' "${SSIDLIST[@]}" | grep -Fwqz $SSID; then
    # echo "Yes the SSID is in the list of known office networks"
    DebugLog "Computer is on a known office network, no lookup required"
	exit
fi
# END known office exemption

#
# has wifi signal changed - if not then exit
if [[ "${use_optim}" == "True" ]] || [[ "${use_optim}" == "true" ]] ; then
	echo "Using Optimization"
	DebugLog "Using Optimzation"
	OldAP=`defaults read "/Library/Application Support/pinpoint/location.plist" TopAP`
	OldSignal=`defaults read "/Library/Application Support/pinpoint/location.plist" Signal` || OldSignal="0"
	NewResult="$(echo $gl_ssids | awk '{print substr($0, 1, 22)}' | sort -t '$' -k2,2rn | head -1)" || NewResult=""
	NewAP="$(echo "$NewResult" | cut -f1 -d '$')" || NewAP=""
	NewSignal="$(echo "$NewResult" | cut -f2 -d '$')" || NewSignal="0"
	if [[ "${NewAP}" == "" ]]; then
		DebugLog "blank AP - problem, quitting"
		exit 1
	fi
	defaults write "$resultslocation" TopAP "$NewAP"
	defaults write "$resultslocation" Signal "$NewSignal"
	let SignalChange=OldSignal-NewSignal
	DebugLog "Old AP: $OldAP $OldSignal"
	DebugLog "New AP: $NewAP $NewSignal"
	DebugLog "signal change: $SignalChange"
	thrshld=18
	moved=0
	if (( SignalChange > thrshld )) || (( SignalChange < -thrshld )) ; then
		moved=1
		DebugLog "significant signal change"
	else
		moved=0
		DebugLog "no significant signal change"
	fi
	
	[ $OldAP ] && [ $NewAP ] && APdiff=$(levenshtein "$OldAP" "$NewAP") || APdiff=17
	
	# check how much alike are the AP MAC addresses
	if [ $APdiff -eq 0 ] ; then
		DebugLog "same AP"
	elif [ $APdiff -eq 1 ] ; then
		DebugLog "same AP, different MAC"
	elif [ $APdiff -eq 2 ] ; then
		DebugLog "probably same AP, different MAC"
	else
		DebugLog "AP change"
		moved=1
	fi

	LastError="$(defaults read "$resultslocation" CurrentStatus | grep Error)"
	LastAddress="$(defaults read "$resultslocation" Address)"

	DebugLog "Last error: $LastError"
	DebugLog "Last address: $LastAddress"
	
#	if [[ -n "${LastError}" ]] ; then
#		DebugLog "Running gelocation due to error last time"
#	fi

#	if (( moved == 1 )) || [[ -n "${LastError}" ]] ; then
	if (( moved == 1 )) ; then
		DebugLog "Running gelocation"
	else
		DebugLog "Boring wifi, leaving"
		defaults write "$resultslocation" LastRun -string "$rundate"
		exit
	fi
fi

OLD_IFS=$IFS
IFS="$"

# Old Google Maps API - no longer works :(
# URL="https://maps.googleapis.com/maps/api/browserlocation/json?browser=firefox&sensor=false"
#
# Using BSSIDs found above we now need to format this as a JSON request so we can send it using the new Google Geolocation api
json="{
  "considerIp": "false",
  "wifiAccessPoints": [
"
# count number of lines
last=`echo -n "$gl_ssids" | grep -c '^'`
exec 5<<< "$gl_ssids"
line=0
while read -u 5 MAC SS SSID CHANNEL
do
	let "line=line+1"
    #SSID=`echo $SSID | sed "s/^ *//g" | sed "s/ *$//g" | sed "s/ /%20/g"`
    MAC=`echo $MAC | sed "s/^ *//g" | sed "s/ *$//g"`
    SS=`echo $SS | sed "s/^ *//g" | sed "s/ *$//g"`
    CHANNEL=`echo $CHANNEL | sed "s/^ *//g" | sed "s/ *$//g" | awk -F'[, \t]*' '{print $1}'`
    json+="	{
    		\"macAddress\": \"$MAC\",
    		\"signalStrength\": $SS,
    		\"age\": 0,
    		\"channel\": $CHANNEL,
    		\"signalToNoiseRatio\": 0
    	}"
    if [ "$line" -lt "$last" ]; then
    	json+=",
    "
    fi
done
json+="
  ]
}"

IFS=$OLD_IFS
#
# Using list of BSSIDs formatted as JSON query Google for location
#echo "$json"
DebugLog "Getting coordinates"
result=$(curl -s -d "$json" -H "Content-Type: application/json" -i "https://www.googleapis.com/geolocation/v1/geolocate?key=$YOUR_API_KEY")
echo "$result"
#
# Get HTTP result code, if 400 it implies it failed, if 200 it succeeded
# A 400 or 404 error might mean none of your detect WiFi BSSIDs are known to Google
resultcode=`echo "$result" | grep "HTTP/2" | awk '{print $2}'`
echo "Result code = $resultcode"
if [ "$resultcode" != "200" ]; then
	if [ -e "$resultslocation" ]; then
		reason=`echo "$result" | grep "reason" | awk -F ": " '{print $2}'`
		message=`echo "$result" | grep "message" | awk -F ": " '{print $2}'`
		defaults write "$resultslocation" CurrentStatus -string "Error $resultcode - $reason"
		defaults write "$resultslocation" LastRun -string "$rundate"
		defaults write "$resultslocation" StaleLocation -string "Yes"
		chmod 644 "$resultslocation"
	fi
	DebugLog "Error: $resultcode"
	#MORE STUFF
	DebugLog "Reason: $reason"
	DebugLog "Message: $message"
	DebugLog "RunDate: $rundate"
	DebugLog "JSON: $json"
	DebugLog "GL_SSIDS: $gl_ssids"
	DebugLog "STDERR: $stderr"
	exit 1
fi
#
# Extract latitude
lat=`echo "$result" | grep lat | awk -F'[, \t]*' '{print $3}'`
#
# Extract longitude
long=`echo "$result" | grep lng | awk '{print $2}'`
#
# Extract accuracy as a radius centered on possible location, the smaller the radius the more accurate it is likely to be
accuracy=`echo "$result" | grep "accuracy" | awk -F ": " '{print $2}'`
#echo "$accuracy"
#
# Create URL to display location using Google Maps
# First version shows using standard map view
googlemap="https://www.google.com/maps/place/$lat,$long/@$lat,$long,18z/data=!4m5!3m4"
# Second version shows using satellite map view
# googlemap="https://www.google.com/maps/place/$lat,$long/@$lat,$long,18z/data=!3m1!1e3"
#

# Calculate if device moved 
# Get last coordinates
oldLat=$(defaults read "$resultslocation" Latitude)
oldLong=$(defaults read "$resultslocation" Longitude)

latMove=$(echo "($lat - $oldLat) * 3000" | bc)
longMove=$(echo "($long - $oldLong) * 3000" | bc)

latMove=$(printf "%.0f\n" $latMove)
longMove=$(printf "%.0f\n" $longMove)
DebugLog "Moved: $latMove $longMove"

if  (( $latMove )) || (( $longMove )) ; then
    echo ""
	DebugLog "Possible coordinate change, going to geocode"
else
	if [[ -n "${LastError}" ]] || [ -z "${LastAddress}" ] ; then
		DebugLog "Running geocode due to error last time"
	else
		DebugLog "geolocation done, no geocode needed"
		use_geocode="False"
	fi	
fi

# Use Google to reverse geocode location to get street address
if [[ "${use_geocode}" == "True" ]] || [[ "${use_geocode}" == "true" ]] ; then
	DebugLog "Getting geocode"
	#address=$(curl -s "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$long")
	# If you get an error saying you need to supply a valid API key then try this line instead
	address=$(curl -s "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$long&key=$YOUR_API_KEY")
	status=`echo "$address" | grep "status" | awk -F ": " '{print $2}' | sed -e 's/^"//' -e 's/.\{1\}$//'`
	echo "status = $status"
	if [ "$status" != "OK" ]; then
		echo "not OK"
		if [ -e "$resultslocation" ]; then
			reason=`echo "$address" | grep "error_message" | awk -F ": " '{print $2}' | sed -e 's/^"//' -e 's/.\{2\}$//'`
			defaults write "$resultslocation" CurrentStatus -string "Error $status - $reason"
			defaults write "$resultslocation" LastRun -string "$rundate"
			defaults write "$resultslocation" StaleLocation -string "Yes"
			chmod 644 "$resultslocation"
		fi
		DebugLog "Error: $status - $reason"
		exit 1
	fi
	#
	# Find first result which is usually best and strip unwanted characters from beginning and end of line
	formatted_address=`echo "$address" | grep -m1 "formatted_address" | awk -F ":" '{print $2}' | sed -e 's/^ "//' -e 's/.\{2\}$//'`
	defaults write "$resultslocation" Address -string "$formatted_address"
	DebugLog "$formatted_address"
else
	formatted_address=""
fi
#
# Use Google to find elevation aka altitude
if [[ "${use_altitude}" == "True" ]] || [[ "${use_altitude}" == "true" ]] ; then
	altitude_result=$(curl -s "https://maps.googleapis.com/maps/api/elevation/json?locations=$lat,$long&key=$YOUR_API_KEY")
	altitude_status=`echo "$altitude_result" | grep -m1 "status" | awk -F ":" '{print $2}' | sed -e 's/^ "//' -e 's/.\{1\}$//'`
	if [ "$altitude_status" != "OK" ]; then
		if [ -e "$resultslocation" ]; then
			reason=`echo "$altitude_result" | grep "error_message" | awk -F ": " '{print $2}' | sed -e 's/^"//' -e 's/.\{2\}$//'`
			defaults write "$resultslocation" CurrentStatus -string "Error $status - $reason"
			defaults write "$resultslocation" LastRun -string "$rundate"
			defaults write "$resultslocation" StaleLocation -string "Yes"
			chmod 644 "$resultslocation"
		fi
		DebugLog "Error: $status - $reason"
		exit 1
	else
		altitude=`echo "$altitude_result" | grep -m1 "elevation" | awk -F ":" '{print $2}' | sed -e 's/^[ \t]*//' -e 's/.\{2\}$//'`
	fi
else
	altitude="0"
fi
#
if [ $jamf -eq 1 ]; then
	echo "<result>$googlemap</result>"
else
	if [ -f "/Library/Preferences/com.jelockwood.pinpoint.plist" ]; then
		[ "$formatted_address" ] && defaults write "$resultslocation" Address -string "$formatted_address"
		[ "$altitude" ] && defaults write "$resultslocation" Altitude -int "$altitude"
		[ "$googlemap" ] && defaults write "$resultslocation" GoogleMap -string "$googlemap"
		[ "$rundate" ] && defaults write "$resultslocation" LastLocationRun -string "$rundate"
		[ "$rundate" ] && defaults write "$resultslocation" LastRun -string "$rundate"
		[ "$lat" ] && defaults write "$resultslocation" Latitude -string "$lat"
		[ "$accuracy" ] && defaults write "$resultslocation" LatitudeAccuracy -int "$accuracy"
		[ "$long" ] && defaults write "$resultslocation" Longitude -string "$long"
		[ "$accuracy" ] && defaults write "$resultslocation" LongitudeAccuracy -int "$accuracy"
		defaults write "$resultslocation" CurrentStatus -string "Successful"
		defaults write "$resultslocation" StaleLocation -string "No"
		chmod 644 "$resultslocation"
	fi
fi

exit
