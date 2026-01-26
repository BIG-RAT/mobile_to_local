#!/bin/bash

currentUser=$(stat -f%Su /dev/console)

user_plist="/Users/${currentUser}/Library/Preferences/com.apple.HIToolbox.plist"
root_plist="/var/root/Library/Preferences/com.apple.HIToolbox.plist"

if [[ -f "$root_plist" ]]; then
	cp -p "$root_plist" "$root_plist.mobile_to_local"
	echo "Backup created: $root_plist.mobile_to_local"
else
	echo "File does not exist: $root_plist"
	touch "$root_plist.delete"
fi

if [[ -f "$user_plist" ]]; then
	cp "$user_plist" "$root_plist"
	chown root:wheel "$root_plist"
	chmod 600 "$root_plist"
	echo "Updated: $root_plist"
else
	echo "File does not exist: $user_plist"
fi