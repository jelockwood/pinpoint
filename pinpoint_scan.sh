#!/bin/sh

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
