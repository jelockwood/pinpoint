#!/usr/bin/env pythonw

# Initial prototype to replace the Apple airport binary located at -
# /System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport
# As of macOS Sonoma 14.4 this binary has been deprecated and no longer works and instead produces the following message
#
# WARNING: The airport command line tool is deprecated and will be removed in a future release.
# For diagnosing Wi-Fi related issues, use the Wireless Diagnostics app or wdutil command line tool.
#
# This script is intended to function as a replacement for using airport -s
#
# Still to do -
# 1. Automate picking the correct network interface as it is not always guaranteed to be 'en0'
# [item 1 now done]
# 2. Update the script to produce results in an identical format to that produced by the former airport binary

import objc
objc.loadBundle(
    "CoreWLAN",
    bundle_path="/System/Library/Frameworks/CoreWLAN.framework",
    module_globals=globals()
)
from CoreWLAN import CWNetwork, CWWiFiClient
client = CWWiFiClient.sharedWiFiClient()
iface = CWWiFiClient.sharedWiFiClient().interface()
# iface = client.interfaceWithName_("en0")
networks, error = iface.scanForNetworksWithName_error_(
    None,
    None,
)

for i in networks:
    if i.ssid() is None:
         continue
    print({'SSID_STR': i.ssid(), 'BSSID': i.bssid(), 'RSSI': i.rssiValue(), 'CHANNEL': i.channel()})
