#!/bin/bash

# Force the script to quit if any error encountered
set -e

osVers=$(sw_vers -productVersion)

appInfo="org.python.python"
appName="Python"

# Initialize array variable to hold admin usernames
list=()
NL=$'\n'

if [[ "$osVers" == *13* ]] ; then
    echo "Executing for macOS Ventura 13 Ventura..."
    for i in $(/usr/libexec/PlistBuddy -c "Print" /var/db/locationd/clients.plist | grep :$appInfo | awk -F '=Dict{' '{gsub(/ /,"");gsub(":","\\:");print $1}'); do
    keyName=$(echo "$i" | awk -v FS=: '{print $2}')
    authValue=$(/usr/LibExec/PlistBuddy -c "Print :$i:Authorized" /var/db/locationd/clients.plist)
    list+=("$keyName: $authValue${NL}")
    done
elif [[ "$osVers" == *14* ]] ; then
    echo "Executing for macOS 14 Sonoma..."
    for i in $(/usr/libexec/PlistBuddy -c "Print" /var/db/locationd/clients.plist | grep -a :i$appInfo | awk -F '=Dict{' '{gsub(/ /,"");gsub(":","\\:");print $1}'  | sed "s/..$//"); do
    keyName=$(echo "$i" | awk -v FS=: '{print $2}')
    authValue=$(/usr/LibExec/PlistBuddy -c "Print :$i\::Authorized" /var/db/locationd/clients.plist)
    list+=("$keyName: $authValue${NL}")
    done
fi

# Print all items in the list array
/bin/echo "<result>${list[@]}</result>"
