#!/usr/local/bin/managed_python3
#
# Copyright John E. Lockwood (2024)
#
# pinpoint_scan.py is a replacement for Apple's airport binary which has been deprecated in macOS Sonoma 14.4
# it produces a scan report of available SSIDs in the same format previously available from Apple's airport tool
# Due to additional changes to CoreWLAN made by Apple it is now necessary to enable access to Location Services for Python
#
# see https://github.com/jelockwood/pinpoint

# Many thanks in particular go to @thewade. He greatly helped with how to format the output as required, how to retrieve
# certain fields of information via CoreWLAN, and also especially helped with the fact that - perhaps counter-intuitively
# Location Services has to be enabled in order to also retreive certain fields of information.
#
# The code to check Location Services is his - I have merely commented out a line

# Checks that Location Services is enabled for Python and exit with error if not
import CoreLocation
import sys
from time import sleep

location_manager = CoreLocation.CLLocationManager.alloc().init()
location_manager.startUpdatingLocation()

max_wait = 6
# Get the current authorization status for Python
for i in range(1, max_wait):
    authorization_status = location_manager.authorizationStatus()
    if authorization_status == 3 or authorization_status == 4:
#        print("Python has been authorized for location services")
        break
    if i == max_wait-1:
        sys.exit("Unable to obtain Location Services authorization, exiting")
    sleep(1)
# End checking of Location Services

import objc
objc.loadBundle(
    "CoreWLAN",
    bundle_path="/System/Library/Frameworks/CoreWLAN.framework",
    module_globals=globals()
)

import CoreWLAN
import re

from CoreWLAN import CWNetwork, CWWiFiClient
iface = CoreWLAN.CWInterface.interface()
networks, error = iface.scanForNetworksWithName_error_(
    None,
    None,
)

print(f"{'SSID' : >32} {'BSSID' : <17} RSSI CHANNEL HT CC SECURITY")

for i in networks:
    if i.ssid() is None:
        continue
    ssidstr = i.ssid().rjust(32)
    if not i.bssid():
        bssidstr = " ".ljust(17)
    if i.bssid():
        bssidstr = i.bssid().ljust(17)
    rssistr = str(i.rssiValue()).ljust(4)
    channelstr = str(i.channel()).ljust(7)
    supportsHT = 'Y' if i.fastestSupportedPHYMode() >= CoreWLAN.kCWPHYMode11n else 'N'
    supportsHTstr = supportsHT.ljust(2)
    if not i.countryCode():
        countrystr = "--".ljust(2)
    if i.countryCode():
        countrystr = i.countryCode().ljust(2)
    securitystr = re.search('security=(.*?),', str(i)).group(1)
    print(ssidstr,bssidstr,rssistr,channelstr,supportsHTstr,countrystr,securitystr)
