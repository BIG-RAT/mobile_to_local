#!/bin/bash

log() {
    echo "$(date "+%a %b %d %H:%M:%S") $computerName ${currentName}[migrate]: $1" >> /var/log/jamf.com
}

jamfH="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
dsclBin="/usr/bin/dscl"
attribsToSkip="dsAttrTypeStandard:RecordType,dsAttrTypeStandard:UserShell,dsAttrTypeStandard:RealName,dsAttrTypeStandard:Password,dsAttrTypeStandard:NFSHomeDirectory,dsAttrTypeStandard:JPEGPhoto,dsAttrTypeStandard:GeneratedUID"
attribsToKeep="RecordName\|RealName\|JPEGPhoto\|UserShell\|GeneratedUID\|NFSHomeDirectory"

## in case the jamf.log does not exist
if [ ! -f /var/log/jamf.log ];then
    touch /var/log/jamf.log
fi

## grab the computer name to use in the log
computerName=$(scutil --get ComputerName)

## new new logon name
newName="$1"
## get logged in user
currentName=$(stat -f%Su /dev/console)

## check the user id to determine if it is a mobile account
idCheck=$(dscl . -read "/Users/$currentName" UniqueID | awk '/: / {print $2}')
if [ $idCheck -lt 1000 ];then
    ## account is a local account
    log("$currentName is a local account.") >> /var/log/jamf.log
    exit 1000
fi

## verify we're either keeping the same username or new name doesn't exist
nameCheck=$(dscl . -read "/Users/$newName" RealName &> /dev/null;echo $?)
if [ "$nameCheck" = "0" ] && [ ! "$newName" == "$currentName" ];then
    ## account already exists and belongs to a different user
    log("$newName belongs to another user.") >> /var/log/jamf.log
    exit 500
fi

log("current user: $currentName") >> /var/log/jamf.log
password="$2"

## renameHomeDir is 0 if we're not renaming the user home directory to the new name (if different the the existing) and 1 if we are
renameHomeDir="$3"

"$jamfH" -windowType fs -iconSize 512 -icon /Applications/Utilities/Migration\ Assistant.app/Contents/Resources/MigrateAsst.icns -description "Completing account migration.  This process may take a few minutes, please stand by..." -alignDescription center -startlaunchd &

sleep 1

## find first available id above 500
id="501"
allUsers=$(dscl . -list /Users UniqueID | awk '{ print $2 }')
isUnique=$(echo "$allUsers" | grep "^$id$")
while [ "$isUnique" != "" ];do
    ((id++))
    isUnique=$(echo "$allUsers" | grep "^$id$")
done
log("new id: $id") >> /var/log/jamf.log

#    ## capture account photo to migrate to the new account
#    JpegPhoto=$(dscl . -read "/Users/$currentName" JPEGPhoto > "/tmp/$currentName.hex"
#    xxd -plain -revert "/tmp/$currentName.hex" > "/tmp/$currentName.png")

## unbind
dsconfigad -remove -force -username "$currentName" -password "$password"
rm '/Library/Preferences/OpenDirectory/Configurations/Active Directory/*.plist'

## remove .accounts file if present
rm -f "/Users/${currentName}/.account" || true

pid=$(ps -ax | grep opendir | grep -v grep | awk '/ / {print $1}')
log("restarting opendirectoryd with pid $pid") >> /var/log/jamf.log
killall opendirectoryd
sleep 1
## wait for opendirectoryd to start back up
pid=$(ps -ax | grep opendir | grep -v grep | awk '/ / {print $1}')
while [ "$pid" = "" ];do
    sleep 1
    pid=$(ps -ax | grep opendir | grep -v grep | awk '/ / {print $1}')
done
log("opendirectoryd restarted with pid $pid") >> /var/log/jamf.log

## create a random file name to hold current account settings
tmpName=$(openssl rand -base64 10 | tr -dc A-Za-z0-9)
## verify the is not already an account with the random name and the name has at least one character
while [[ "$(dscl . -read /Users/$tmpName UniqueID 2>&1>/dev/null;echo $?)" = "0" ]] || [[ "${#tmpName}" = "0" ]];do
    sleep 1
    tmpName=$(openssl rand -base64 10 | tr -dc A-Za-z0-9)
done
dsexport "/tmp/${tmpName}.dse" /Local/Default dsRecTypeStandard:Users -r "${currentName}"

realName=$($dsclBin . -read "/Users/$currentName" RealName | tail -n1 | cut -c 2-)
log("mobile user RealName: $realName") >> /var/log/jamf.log

currentMobileUserHome=$($dsclBin . -read "/Users/$currentName" NFSHomeDirectory | awk -F': ' '{print $2}')
log("mobile user home: $currentMobileUserHome") >> /var/log/jamf.log

log("renaming mobile account to ${tmpName}") >> /var/log/jamf.log
$dsclBin . -change "/Users/$currentName" RecordName "$currentName" "${tmpName}"
sleep 1
log("creating local user $newName") >> /var/log/jamf.log
$dsclBin . -create "/Users/${newName}"
log("setting RealName to $realName") >> /var/log/jamf.log
$dsclBin . -create "/Users/${newName}" RealName "$realName"
$dsclBin . -passwd "/Users/${newName}" "$password"
$dsclBin . -create "/Users/${newName}" UniqueID $id
$dsclBin . -create "/Users/${newName}" PrimaryGroupID 20

## remove attributes from mobile account - start
while read theAttribute;do
    log("deleting attribute: $theAttribute") >> /var/log/jamf.log
    dscl . -delete "/Users/${tmpName}" $theAttribute
#    echo $?
done << EOL
$($dsclBin -raw . -read "/Users/${tmpName}" | grep dsAttrType | awk -F":" '{print $2}' | grep -v "$attribsToKeep")
EOL
## remove attributes from mobile account - end

mkdir -p "/tmp/exported/"
dsexport "/tmp/exported/${newName}.dse" /Local/Default dsRecTypeStandard:Users -r "${newName}" -e "$attribsToSkip"
log("attributes to write to new account: $(cat /tmp/exported/${newName}.dse)") >> /var/log/jamf.log

result=$($dsclBin . -delete "/Users/${newName}";echo "$?")
if [ "$result" == "0" ];then
    log("deleted account ${newName}") >> /var/log/jamf.log
fi

log("attributes to write to new account: $(cat /tmp/exported/${newName}.dse)") >> /var/log/jamf.log
sleep 1
result=($dsclBin . -change "/Users/${tmpName}" RecordName "${tmpName}" "${newName}";echo "$?")
if [ "$result" == "0" ];then
log("deleted account ${newName}") >> /var/log/jamf.log
fi

sleep 1
dsimport "/tmp/exported/${newName}.dse" /Local/Default M

sleep 1
## ensure we have the correct password
$dsclBin . -passwd "/Users/${newName}" "$password"
$dsclBin . -delete "/Users/${newName}" "PrimaryDomain"
$dsclBin . -delete "/Users/${newName}" "AppleMetaRecordName"

## ensure proper owner/group on home directory
chown -R "$id:staff" "$currentMobileUserHome" &> /dev/null
log("updated owner:group for home directory") >> /var/log/jamf.log
log("chown -R $id:staff $currentMobileUserHome") >> /var/log/jamf.log

## set permissions on user owned folders outside the /Users folder
# BEGIN PERMISSIONS LOOKUP
# No loop required, Find executes the chown command on every line result by nature. Only sets the owner, leaves group 'as is'
#echo "Searching inside /usr/local"
##        id of AD account: $idCheck
## id of new local account: $id
find /usr/local -user $idCheck -exec chown $id {} \;
#echo "Searching inside /opt"
find /opt/ -user $idCheck -exec chown $id {} \;
#echo "Searching inside /Users/Shared"
find /Users/Shared -user $idCheck -exec chown $id {} \;

## if we changed shortnames, add the old one as an alias
if [ "${newName}" != "${currentName}" ];then
    log("login name has changed") >> /var/log/jamf.log
    log("adding alias for old username: ${currentName}") >> /var/log/jamf.log
    $dsclBin . -append "/Users/${newName}" RecordName "$currentName"
    if [ "${renameHomeDir}" == "1" ];then
        log("setting home directory to /Users/${newName}") >> /var/log/jamf.log
        $dsclBin . -change "/Users/${newName}" NFSHomeDirectory "${currentMobileUserHome}" "/Users/${newName}"
        mv "${currentMobileUserHome}" "/Users/${newName}"
    fi
fi


log("killing jamfHelper and loginwindow") >> /var/log/jamf.log

sudo killall jamfHelper
#sudo killall loginwindow &
loggedInUser=`/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }' | grep -v root`
ps -Ajc | grep loginwindow | grep "$loggedInUser" | grep -v grep | awk '{print $2}' | sudo xargs kill &
log("loginwindow restarted.") >> /var/log/jamf.log &

#rm -fr $0
