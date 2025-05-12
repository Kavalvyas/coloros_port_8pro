#!/bin/bash
device_code=$1
case $device_code in
	OnePlus9R) size=9932111872;;
	OnePlus8T) size=7516192768;;
    OnePlus8 | OnePlus8Pro) size=15032385536;;
	#Oppo find X3
	OP4E5D)  size=11190403072;;
	#Others
	*) size=11811160064;;
esac
echo $size