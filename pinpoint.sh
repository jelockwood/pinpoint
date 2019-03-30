#!/bin/sh
# Copyright John E. Lockwood (2018-2019)
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
versionstring="3.0.3"
# get date and time in UTC hence timezone offset is zero
rundate=`date -u +%Y-%m-%d\ %H:%M:%S\ +0000`
#echo "$rundate"
#
# help information
usage()
{
    echo "usage: $scriptname [-V] [-j] [-h] [-g] [-a] [-k yourkeyhere]
	-V | --version		Print script version and exit
	-j | --jamf		Return map URL only to stdout formatted as an
    				extension attribute for use with JAMF Pro
	-h | --help		show this help message and exit
	-g | --geocode		Use Geocode API to look up street address
	-a | --altitude		Use Elevation API to look up altitude
	-k | --key yourkeyhere	Specify your Google API key"
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
		/usr/bin/python -c "from Foundation import CFPreferencesCopyAppValue; print CFPreferencesCopyAppValue(\"$2\", \"$1\")"
	}

	use_geocode=$(pref_value ${DOMAIN} "USE_GEOCODE")
	use_altitude=$(pref_value ${DOMAIN} "USE_ALTITUDE")
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
# Location of plist with results
resultslocation="/Library/Application Support/pinpoint/location.plist"
#

#
# Get list of network interfaces, find WiFi interface
# Get status of WiFi interface i.e. whether it is already turned on
# If off turn it on as it is needed to get the list of BSSIDs in your location
# It is not necessary to actually connect to any WiFi network
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
result=$(curl -s -d "$json" -H "Content-Type: application/json" -i "https://www.googleapis.com/geolocation/v1/geolocate?key=$YOUR_API_KEY")
echo "$result"
#
# Get HTTP result code, if 400 it implies it failed, if 200 it succeeded
# A 400 or 404 error might mean none of your detect WiFi BSSIDs are known to Google
resultcode=`echo "$result" | grep "HTTP" | awk '{print $2}'`
echo "Result code = $resultcode"
if [ $resultcode != "200" ]; then
	if [ -e "$resultslocation" ]; then
		reason=`echo "$result" | grep "HTTP" | awk -F ": " '{print $2}'`
		defaults write "$resultslocation" CurrentStatus -string "Error $resultcode - $reason"
		defaults write "$resultslocation" LastRun -string "$rundate"
		defaults write "$resultslocation" StaleLocation -string "Yes"
		chmod 644 "$resultslocation"
	fi
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
oldLat=$(defaults read "$resultslocation" Latitude -string)
oldLong=$(defaults read "$resultslocation" Longitude -string)

latMove=$(python -c "print (($lat - $oldLat)*10000)")
longMove=$(python -c "print (($long - $oldLong)*10000)")

latMove=$(printf "%.0f\n" $latMove)
longMove=$(printf "%.0f\n" $longMove)

latMove=$((latMove))
longMove=$((longMove))

if [[ (( "$latMove" != 0 )) || ((  "$longMove" != 0 )) ]] ; then
    use_geocode="True"
else
	use_geocode="False"
fi
#

# Use Google to reverse geocode location to get street address
if [ "$use_geocode" == "True" ]; then
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
		exit 1
	fi
	#
	# Find first result which is usually best and strip unwanted characters from beginning and end of line
	formatted_address=`echo "$address" | grep -m1 "formatted_address" | awk -F ":" '{print $2}' | sed -e 's/^ "//' -e 's/.\{2\}$//'`
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
		if [ "$ls_enabled" == "True" ]; then
			defaults write "$resultslocation" LS_Enabled -bool TRUE
		else
			defaults write "$resultslocation" LS_Enabled -bool FALSE
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
