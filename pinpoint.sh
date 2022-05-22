#!/bin/bash
# Copyright John E. Lockwood (2018-2020)
#
# pinpoint a script to find your Mac's location
#
# see https://github.com/jelockwood/pinpoint
#
# Now written to not use Location Services
#
# Script name
scriptname=$(basename -- "$0")
# Version number
versionstring="3.1.1"
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
	[ $use_debug = "True" ] && echo "$1" >> "$debugLog" && echo "$1"
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
		/usr/local/munkireport/munkireport-python3 -c "from Foundation import CFPreferencesCopyAppValue; print CFPreferencesCopyAppValue(\"$2\", \"$1\")"
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
	echo "Invalid Google API key"
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

#
# has wifi signal changed - if not then exit
if [ "$use_optim" = "True" ] ; then
	NewResult=""
	OldResult="$(cat /tmp/pinpoint-wifi-scan.txt)" || OldResult=""
	NewResult="$(echo $gl_ssids | awk '{print substr($0, 1, 22)}' | sort -t '$' -k2,2rn | head -1)"
	echo "$NewResult" > /tmp/pinpoint-wifi-scan.txt
	#
	# omit last char of MAC
	OldAP="$(echo "$OldResult" | awk '{print substr($0, 1, 17)}')"
	NewAP="$(echo "$NewResult" | awk '{print substr($0, 1, 17)}')"
	OldSignal="$(echo "$OldResult" | awk '{print substr($0, 19, 4)}')"
	NewSignal="$(echo "$NewResult" | awk '{print substr($0, 19, 4)}')"
	test $OldSignal || OldSignal="0"
	test $NewSignal || NewSignal="0"
	SignalChange=$(/usr/local/munkireport/munkireport-python3 -c "print ($OldSignal - $NewSignal)")
	DebugLog "$(date)"
	DebugLog "$OldAP $OldSignal"
	DebugLog "$NewAP $NewSignal"
	DebugLog "signal change: $SignalChange"

	if [ $SignalChange -gt 12 ] || [ $SignalChange -lt -12 ] ; then
		moved=1
		DebugLog "significant signal change"
	else
		moved=0
		DebugLog "no significant signal change"
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

	LastStatus="$(defaults read "$resultslocation" CurrentStatus | grep 403)"
	LastAddress="$(defaults read "$resultslocation" Address)"


	if ! (( $moved ))  ; then
		DebugLog "Last status $LastStatus"
		DebugLog "Last address $LastAddress"
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

latMove=$(/usr/local/munkireport/munkireport-python3 -c "print (($lat - $oldLat)*3000)")
longMove=$(/usr/local/munkireport/munkireport-python3 -c "print (($long - $oldLong)*3000)")

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
if [ "$use_geocode" == "True" ]; then
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
if [ "$use_altitude" == "True" ]; then
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
	if [ -e "/Library/Preferences/com.jelockwood.pinpoint.plist" ]; then
		defaults write "$resultslocation" Address -string "$formatted_address"
		defaults write "$resultslocation" Altitude -int "$altitude"
		defaults write "$resultslocation" CurrentStatus -string "Successful"
		defaults write "$resultslocation" GoogleMap -string "$googlemap"
		# Even though this version of pinpoint has been deliberately written not to use Location Services at all
		# we check to see if Location services is or is not enabled and report this.
		# This is done in order to be backwards compatible with the previous Location Services based version of pinpoint
		ls_enabled=`defaults read "/var/db/locationd/Library/Preferences/ByHost/com.apple.locationd" LocationServicesEnabled`
		echo "ls_enabled = $ls_enabled"
		if [ "$ls_enabled" == "1" ]; then
			defaults write "$resultslocation" LS_Enabled -int 1
		else
			defaults write "$resultslocation" LS_Enabled -int 0
		fi
		defaults write "$resultslocation" LastLocationRun -string "$rundate"
		defaults write "$resultslocation" LastRun -string "$rundate"
		defaults write "$resultslocation" Latitude -string "$lat"
		defaults write "$resultslocation" LatitudeAccuracy -int "$accuracy"
		defaults write "$resultslocation" Longitude -string "$long"
		defaults write "$resultslocation" LongitudeAccuracy -int "$accuracy"
		defaults write "$resultslocation" StaleLocation -string "No"
		chmod 644 "$resultslocation"
	fi
fi

exit 0