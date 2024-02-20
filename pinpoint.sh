#!/bin/bash
# Copyright John E. Lockwood (2018-2024)
#
# pinpoint a script to find your Mac's location
#
# see https://github.com/jelockwood/pinpoint
#
# Now written to not use Location Services
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
versionstring="3.2.5"
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

debugLog="/var/log/pinpoint.log"

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

# Set your Google geolocation API key here
# You can get an API key here https://developers.google.com/maps/documentation/geolocation/get-api-key
#
# Set API key in script - mainly for use with JAMF
YOUR_API_KEY="pasteyourkeyhere"
#
# Set initial default preference values
use_geocode="True"
use_altitude="False"
use_optim="True"
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
		-d | --debug )		use_debug=1
						commandoptions=1
						;;
		-o | --optim )		use_optim=1
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
DebugLog "### pinpoint run ###"
DebugLog "$(date)"

INTERFACE=$(networksetup -listallhardwareports | grep -A1 Wi-Fi | tail -1 | awk '{print $2}')
STATUS=$(networksetup -getairportpower $INTERFACE | awk '{print $4}')
if [ $STATUS = "Off" ] ; then
    networksetup -setairportpower $INTERFACE on
    sleep 5
fi
#
# Now use built-in Apple tool to get list of BSSIDs
gl_ssids=`/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport -s | tail -n +2 | awk '{print substr($0, 34, 17)"$"substr($0, 52, 4)"$"substr($0, 1, 32)"$"substr($0, 57, 3)}' | sort -t $ -k2,2rn | head -12`
#
# We have finished using the WiFi if it was originally off we now turn it back off
if [ $STATUS = "Off" ] ; then
    networksetup -setairportpower $INTERFACE off
fi

if [[ -z "${gl_ssids}" ]]; then
	DebugLog "airport cmd failed"
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

#
# has wifi signal changed - if not then exit
if [[ "${use_optim}" == "True" ]] || [[ "${use_optim}" == "true" ]] ; then
	OldAP=`defaults read "/Library/Application Support/pinpoint/location.plist" TopAP`
	OldSignal=`defaults read "/Library/Application Support/pinpoint/location.plist" Signal` || OldSignal="0"
	NewResult="$(echo $gl_ssids | awk '{print substr($0, 1, 22)}' | sort -t '$' -k2,2rn | head -1)" || NewResult=""
	NewAP="$(echo "$NewResult" | cut -f1 -d '$')" || NewAP=""
	NewSignal="$(echo "$NewResult" | cut -f2 -d '$')" || NewSignal="0"
	defaults write "$resultslocation" TopAP "$NewAP"
	defaults write "$resultslocation" Signal "$NewSignal"
	let SignalChange=OldSignal-NewSignal
	DebugLog "Old AP: $OldAP $OldSignal"
	DebugLog "New AP: $NewAP $NewSignal"
	DebugLog "signal change: $SignalChange"
	thrshld=18
	if (( SignalChange > thrshld )) || (( SignalChange < -thrshld )) ; then
		moved=1
		DebugLog "significant signal change"
	else
		moved=0
		DebugLog "no significant signal change"
	fi

	if [[ "${NewAP}" == "" ]]; then
		DebugLog "blank AP - problem, quitting"
		exit 1
	fi
	
	[ $OldAP ] && [ $NewAP ] && APdiff=$(levenshtein "$OldAP" "$NewAP") || APdiff=17
	if [ $APdiff -eq 0 ] ; then
		DebugLog "same AP"
	elif [ $APdiff -eq 1 ] ; then
		DebugLog "same AP, different SSID"
	else
		DebugLog "AP change"
		moved=1
	fi

	LastStatus="$(defaults read "$resultslocation" CurrentStatus | grep Error)"
	LastAddress="$(defaults read "$resultslocation" Address)"

	if ! (( $moved ))  ; then
		DebugLog "Last error: $LastStatus"
		DebugLog "Last address: $LastAddress"
		if [ "$LastStatus" ] || [ -z "$LastAddress" ] ; then
			DebugLog "Running gelocation due to error last time"
		else
			DebugLog "Boring wifi, leaving"
			defaults write "$resultslocation" LastRun -string "$rundate"
			exit 0
		fi
	fi
#
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
		defaults write "$resultslocation" CurrentStatus -string "Error $resultcode - $reason"
		defaults write "$resultslocation" LastRun -string "$rundate"
		defaults write "$resultslocation" StaleLocation -string "Yes"
		chmod 644 "$resultslocation"
	fi
	DebugLog "Error: $resultcode"
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
	if [ "$LastStatus" ] || [ -z "$LastAddress" ] ; then
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
		DebugLog "Error: $status"
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
		DebugLog "Error: $reason"
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

exit 0
