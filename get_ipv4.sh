#!/bin/bash

# This script try to ensure gets the current IP address (as assigned by the ISP) from
# OpenDNS and other online services as fallbacks

hosts=("checkip.amazonaws.com" "api.ipify.org" "ifconfig.me/ip" "icanhazip.com" "ipinfo.io/ip" "ipecho.net/plain" "checkipv4.dedyn.io")

CURL=`which curl`
DIG=`which dig`

check=$($DIG +short myip.opendns.com @resolver1.opendns.com A) 

if [ ! $? -eq 0 ] || [ -z "$check" ] || [[ ! $check =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unable to get your public IP address by OpenDNS service, try to another way."
    count=${#hosts[@]}

    while [ -z "$check" ] && [[ $count -ne 0 ]]; do
        selectedhost=${hosts[ $RANDOM % ${#hosts[@]} ]}
        check=$($CURL -4s https://$selectedhost | grep '[^[:blank:]]') && {
            if [ -n "$check" ] && [[ $check =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                break
            else
                check=""
                count=$(expr $count - 1)
                echo "The host $selectedhost returned an invalid IP address."
            fi
        } || {
            check=""
            count=$(expr $count - 1)
            echo "The host $selectedhost did not respond."
        }
    done
fi

if [ -z "$check" ]; then
    echo "Unable to get your public IP address. Please check your internet connection."
    exit 1
fi

echo "Your public IP address is $check"

exit 0
