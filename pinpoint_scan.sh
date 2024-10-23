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
# Version 1.0, Copyright John Lockwood, October 23rd 2024

lines=$(system_profiler SPAirPortDataType -json)

BSSID="                 "
HT="Y "
CC="--"

echo "                            SSID BSSID             RSSI CHANNEL HT CC SECURITY (auth/unicast/group)"

while read line
do
    if [[ "$line" == "]," ]]
    then
	break
    else
	if echo "$line" | grep -q "_name"
	then
		name=$(echo "$line" | awk -F'"' '{print $4}')
		name=$(printf '%32s' "$name")
	else
		if echo "$line" | grep -q "spairport_network_channel"
		then
			channel=$(echo "$line" | awk -F'"' '{print $4}' | awk -F' ' '{print $1}')
			channel=$(printf '%-7s' "$channel")
		else
			if echo "$line" | grep -q "spairport_security_mode"
			then
				securitymode=$(echo "$line" | awk -F'"' '{print $4}' | sed -e "s/^spairport_security_mode_//" -e "s/_/ /g" -e "s/wpa/WPA/g" -e "s/personal/Personal/" -e "s/enterprise/Enterprise/" -e "s/mixed/Mixed/" -e "s/none/Open/")
			else
				if echo "$line" | grep -q "spairport_signal_noise"
				then
					signalnoise=$(echo "$line" | awk -F'"' '{print $4}' | awk -F' ' '{print $1}')
					signalnoise=$(printf '%-4s' "$signalnoise")
				else
					if echo "$line" | grep -q "},"
					then
						echo "$name $BSSID $signalnoise $channel $HT $CC $securitymode"
					fi
				fi
			fi
		fi
	fi
    fi
done <<< "$(echo -e "$lines")"
