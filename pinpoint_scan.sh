#!/bin/sh
#
# A script to replicate the previous functionality provided by Apple's former 
# /System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport
# tool which was deprected in macOS 14.4. This script uses the /usr/sbin/system_profiler tool.
# This script takes the output and reformats it to reproduce the WiFi SSID report of the former
# airport tool. Due to some differences in capabilities of system_profiler some information is
# not possible to produce and these fields are left empty or with fake data. These fields being
# BSSID, HT and CC but are fortunately less important.
#
# Version 1.0.1, Copyright John Lockwood, October 23rd 2024

# Get raw WiFi data in json format
lines=$(/usr/sbin/system_profiler SPAirPortDataType -json)

# Set fields that are not supported to dummy/empty values
BSSID="                 "
HT="Y "
CC="--"

# Output header line
echo "                            SSID BSSID             RSSI CHANNEL HT CC SECURITY (auth/unicast/group)"

# Loop through results and find each SSID and output the fields per SSID in desired format
while read line
do
    if [[ "$line" == "]," ]]
    then
	break
    else
	if echo "$line" | /usr/bin/grep -q "_name"
	then
		name=$(echo "$line" | /usr/bin/awk -F'"' '{print $4}')
		name=$(printf '%32s' "$name")
	else
		if echo "$line" | /usr/bin/grep -q "spairport_network_channel"
		then
			channel=$(echo "$line" | /usr/bin/awk -F'"' '{print $4}' | /usr/bin/awk -F' ' '{print $1}')
			channel=$(printf '%-7s' "$channel")
		else
			if echo "$line" | /usr/bin/grep -q "spairport_security_mode"
			then
				securitymode=$(echo "$line" | /usr/bin/awk -F'"' '{print $4}' | /usr/bin/sed -e "s/^spairport_security_mode_//" -e "s/^pairport_security_mode_//" -e "s/_/ /g" -e "s/wpa/WPA/g" -e "s/personal/Personal/" -e "s/enterprise/Enterprise/" -e "s|WPA3 transition|WPA2/WPA3 Personal|" -e "s/mixed/Mixed/" -e "s/none/Open/")
			else
				if echo "$line" | /usr/bin/grep -q "spairport_signal_noise"
				then
					signalnoise=$(echo "$line" | /usr/bin/awk -F'"' '{print $4}' | /usr/bin/awk -F' ' '{print $1}')
					signalnoise=$(printf '%-4s' "$signalnoise")
				else
					if echo "$line" | /usr/bin/grep -q "},"
					then
						echo "$name $BSSID $signalnoise $channel $HT $CC $securitymode"
					fi
				fi
			fi
		fi
	fi
    fi
done <<< "$(echo -e "$lines")"
