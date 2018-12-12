#! /bin/bash
#===============================================================================
# Title: Wake On LAN Discovery Shell Script for Linux
# Desc: Discover IPv4 devices on LAN. 
#       Following information is discovered:
#       hostname, MAC address, network adapter, broadcast IP
# Synopsis: wol-discovery.sh [results-limit]
# Optional Dependencies debian: avahi-utils, samba-common-bin
# License: Eclipse Public License v2.0 <https://www.eclipse.org/legal/epl-2.0/>
# Author: Ganesh Ingle <ganesh.ingle@asvilabs.com>
# Sample Output:
#   time-capsule.local b8:c7:5d:ce:eb:ad eth0 10.1.255.255
#   LibreELEC.local 94:de:80:76:97:ch eth1 192.168.1.255
# Note: This script is packaged inside wakeonlan bundle jar. You don't have to
#       install it manually
#===============================================================================
export PATH="/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/sbin:/usr/local/bin"

RESULTS_LIMIT=$1
[[ ! $RESULTS_LIMIT =~ ^[0-9]+$ ]] && RESULTS_LIMIT=253

## Refresh ARP cache
# Send braodcast ping on all interfaces
ip link show | grep "UP" | grep -v LOOPBACK | awk -F":" '{print $2}' | xargs -I'{}' ping -c3 -w5 -b 255.255.255.255 -I '{}' &>/dev/null
if [ -n "`type -P avahi-browse`" ] ; then
    avahi-browse --domain=local --all --terminate &>/dev/null
fi
# Ping STALE arp entries
ip -r -4 neigh | grep --color=never --extended-regex "(STALE)|(RESOLVED)" | head -n $RESULTS_LIMIT | cut -d" " -f1 | xargs --no-run-if-empty --max-procs 8 -I'{}' ping -c3 -w5 '{}' >/dev/null

## Collect REACHABLE arp entries
OLD_IFS="$IFS"
IFS=$'\n'
declare -a arpReachable=( $(ip -r -4 neigh|grep --color=never --extended-regex "(DELAY)|(REACHABLE)") )
IFS="$OLD_IFS"
count=0
for arpEntry in "${arpReachable[@]}" ; do
    count=$((count+1))
    [ $count -gt $RESULTS_LIMIT ] && exit 0
    hostname=""
    host=""
    mac=""
    dev=""
    hostIpTest=""
    hostIsIp=""
    declare -a arpFields=( $arpEntry )
    host=${arpFields[0]}
    mac=${arpFields[4]}
    dev=${arpFields[2]}
    [ -z "$host" ] && continue
    [ -z "$mac" ] && continue
    [ -z "$dev" ] && continue
    hostIpTest=${host//\./}
    if [[ $hostIpTest =~ ^[0-9]+$ ]] ; then
        hostIsIp=yes
        #echo "$host is IP"
        if [ -z "$hostname" ] && [  -n "`type -P avahi-resolve`" ] ; then
            hostnameMDNS=$(avahi-resolve --address $host 2>/dev/null | grep -i -v --extended-regex "(failed)|(not found)|(timeout)" | awk "/$host/ { print \$2 }" 2>/dev/null)
            [ -n "$hostnameMDNS" ] && { hostname="$hostnameMDNS"; hostIsIp=no; }
        fi
        if [ -z "$hostname" ] && [ -n "`type -P nmblookup`" ] ; then
            hostnameNMB=$(nmblookup -A $host 2>/dev/null | grep '<00' | grep -v GROUP | awk '{print $1}' 2>/dev/null)
            [ -n "$hostnameNMB" ] && { hostname="$hostnameNMB"; hostIsIp=no; }
        fi
        if [ -z "$hostname" ] && [ -n "`type -P systemd-resolve`" ] ; then
            hostnameSystemdResolvd=$(systemd-resolve $host 2>/dev/null | awk "/$host%$dev/ { print \$2 }" 2>/dev/null )
            [ -n "$hostnameSystemdResolvd" ] && { hostname="$hostnameSystemdResolvd"; hostIsIp=no; }
        fi
        if [ -z "$hostname" ] && [ -n "`type -P host`" ] ; then
            hostnameDNS=$(host $host 2>/dev/null | awk "/domain name pointer/ { print \$5 }")
            [ -n "$hostnameDNS" ] && { hostname="$hostnameDNS"; hostIsIp=no; }
        fi
        if [ -z "$hostname" ] ; then
            hostname=$host
        fi
    else
        hostname=$host
        hostIsIp=no
    fi
    if [ "$hostIsIp" == "no" ] ; then
        if [[ ! $hostname =~ \. ]] ; then
            # Not a FQDN
            # Check if ping can resolve hostname, or append .local suffix
            ping -c1 -w1 $hostname 2>&1 | grep -i --extended-regex "(No address)|(not known)" >/dev/null && hostname="$hostname.local"
        fi
        # Check if ping can resolve hostname, or revert back to IP
        ping -c1 -w1 $hostname 2>&1 | grep -i --extended-regex "(No address)|(not known)" >/dev/null && hostname=$host
    fi
    broad=$(ifconfig $dev|awk '/inet .*broadcast/ { print $6 }')
    echo "$hostname $mac $dev $broad"
done

