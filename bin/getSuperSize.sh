#!/bin/bash
device_code=$1
case $device_code in
    OnePlus8Pro) size=15032385536;;
	#Others (fallback for compatibility)
	*) size=15032385536;;
esac
echo $size