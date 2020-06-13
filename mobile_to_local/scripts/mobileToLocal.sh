#!/bin/bash

## passed variables
## $1 - new username
## $2 - password for user
## $3 - indicate if we're changing the home directory name; 0 - no change, 1 - change
## $4 - type of user to create; standard or admin
## $5 - whether or not to unbind

log() {
    /bin/echo "$(date "+%a %b %d %H:%M:%S") $computerName ${currentName}[migrate]: $1" >> /var/log/jamf.log
}

jamfH="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
dsclBin="/usr/bin/dscl"

## standard attributes for a local account - these will not be deleted from the mobile account
attribsToKeep="_writers_AvatarRepresentation\|_writers_hint\|_writers_jpegphoto\|_writers_passwd\|_writers_picture\|_writers_unlockOptions\|_writers_UserCertificate\|accountPolicyData\|AvatarRepresentation\|HeimdalSRPKey\|KerberosKeys\|LinkedIdentity\|record_daemon_version\|ShadowHashData\|unlockOptions\|AltSecurityIdentities\|AppleMetaNodeLocation\|AuthenticationAuthority\|GeneratedUID\|JPEGPhoto\|NFSHomeDirectory\|Password\|Picture\|PrimaryGroupID\|RealName\|RecordName\|RecordType\|UniqueID\|UserShell"

## in case the jamf.log does not exist
if [ ! -f /var/log/jamf.log ];then
    /usr/bin/touch /var/log/jamf.log
fi

## grab the computer name to use in the log
computerName=$(scutil --get ComputerName)

## new new logon name
newName="$1"
## get logged in user
currentName=$(stat -f%Su /dev/console)

## check admin status
isAdmin=$(/usr/sbin/dseditgroup -o checkmember -m "${currentName}" admin | cut -d" " -f1)
log "result of isAdmin check: ${isAdmin}"

## check the OriginalNodeName to determine if it is a local or mobile account
mobileUserCheck=$($dsclBin . -read "/Users/$currentName" OriginalNodeName 2>/dev/null | grep -v dsRecTypeStandard)
if [ "${mobileUserCheck}" = "" ];then
    ## account is a local account
    log "$currentName is a local account."
    exit 1000
fi

## verify we're either keeping the same username or new name doesn't exist
nameCheck=$(dscl . -read "/Users/$newName" RealName &> /dev/null;echo $?)
if [ "$nameCheck" = "0" ] && [ ! "$newName" = "$currentName" ];then
    ## account already exists and belongs to a different user
    log "$newName belongs to another user."
    exit 500
fi

log "current user: ${currentName}"
password="$2"

## renameHomeDir is 0 if we're not renaming the user home directory to the new name (if different the the existing) and 1 if we are
renameHomeDir="$3"

## set user type to create, if passed, to be either standard or admin.  If nothing is passed local will match mobile account
userType="$4"

## set the unbind var; 'true' or 'false'
unbind="$5"

"$jamfH" -windowType fs -iconSize 512 -icon /Applications/Utilities/Migration\ Assistant.app/Contents/Resources/MigrateAsst.icns -description "Completing account migration.  This process may take a few minutes, please stand by..." -alignDescription center -startlaunchd &

sleep 1

## see if account is FileVault enabled
FileVaultUserCheck=$(fdesetup list | grep -w "${currentName}")
if [ "${FileVaultUserCheck}" != "" ];then
    log "${currentName} is a FileVault enabled user"
else
    log "${currentName} is not a FileVault enabled user"
fi

#    ## capture account photo to migrate to the new account
#    JpegPhoto=$(dscl . -read "/Users/$currentName" JPEGPhoto > "/tmp/$currentName.hex"
#    xxd -plain -revert "/tmp/$currentName.hex" > "/tmp/$currentName.png")

if [ "$unbind" == "true" ];then
## unbind
    /usr/sbin/dsconfigad -remove -force -username "$currentName" -password "${password}"
    /bin/rm "/Library/Preferences/OpenDirectory/Configurations/Active Directory/*.plist"
fi

## remove .accounts file if present
/bin/rm -f "/Users/${currentName}/.account" || true

aa=$($dsclBin -plist . -read /Users/"${currentName}" AuthenticationAuthority)
log "original AuthenticationAuthority from mobile account:"
log "${aa}"
lcu=$(/bin/echo "${aa}" | xmllint --xpath 'string(//string[contains(text(),";LocalCachedUser;")])' -)
krb5=$(/bin/echo "${aa}" | xmllint --xpath 'string(//string[contains(text(),";Kerberosv5;")])' -)

$dsclBin -plist . -delete /Users/"${currentName}" AuthenticationAuthority "${lcu}"
$dsclBin -plist . -delete /Users/"${currentName}" AuthenticationAuthority "${krb5}"

pid=$(ps -ax | grep opendir | grep -v grep | awk '/ / {print $1}')
echo "restarting opendirectoryd with pid $pid"
killall opendirectoryd
sleep 1
## wait for opendirectoryd to start back up
pid=$(ps -ax | grep opendir | grep -v grep | awk '/ / {print $1}')
while [ "$pid" = "" ];do
    sleep 1
    pid=$(ps -ax | grep opendir | grep -v grep | awk '/ / {print $1}')
done
echo "opendirectoryd restarted with pid $pid"


## export updated AuthenticationAuthority for the account
localAuthenticationAuthority=$($dsclBin . -read /Users/"${currentName}" AuthenticationAuthority)
log "AuthenticationAuthority for local account:"
localAuthenticationAuthority=$($dsclBin -plist . -read /Users/"${currentName}" AuthenticationAuthority)
log "${localAuthenticationAuthority}"

## remove attributes from mobile account - start
while read theAttribute;do
    log "deleting attribute: $theAttribute"
    $dsclBin . -delete "/Users/${currentName}" $theAttribute
    #    echo $?
done << EOL
$($dsclBin -raw . -read "/Users/${currentName}" | grep dsAttrType | awk -F":" '{print $2}' | grep -v -w "${attribsToKeep}")
EOL
## remove attributes from mobile account - end

#### for testing to pause the script ####
#touch /Users/Shared/pause.txt
#while [ -f /Users/Shared/pause.txt ];do
#    sleep 10
#done

## ensure proper group on home directory
## skipping the change of group permissions on the user folder to avoide PPPC prompts for contacts and calendars
#homeDir=$($dsclBin . -read /Users/"${currentName}" NFSHomeDirectory | awk -F": " '{ print $2 }')
#log "Setting group and permissions for ${homeDir}"
#result=$(chown -R ":staff" "${homeDir}" &> /dev/null;echo "$?")
#if [ "$result" = "0" ];then
#    log "updated group for home directory"
#    log "chown -R :staff ${homeDir}"
#fi

## add to the admins group, if appropriate
if (([ "${isAdmin}" = "yes" ] && [ "$userType" != "standard" ]) || [ "$userType" = "admin" ]);then
    result=$(/usr/sbin/dseditgroup -o edit -n /Local/Default -a "${currentName}" -t user admin;echo "$?")
    if [ "$result" = "0" ];then
        log "${currentName} was added to the admin group"
    fi
elif [ "$userType" = "standard" ];then
    result=$(/usr/sbin/dseditgroup -o edit -n /Local/Default -d "${currentName}" -t user admin;echo "$?")
    if [ "$result" = "0" ];then
        log "${currentName} was removed from the admin group"
    fi
fi

## if we changed shortnames update the RecordName attribute and add the old name as an alias
if [ "${newName}" != "${currentName}" ];then
    log "login name has changed"
    log "Changing the Record name to ${newName}"
    $dsclBin . -change "/Users/${currentName}" RecordName "${currentName} ${newName}"
    log "adding alias for old username: ${currentName}"
    $dsclBin . -append "/Users/${newName}" RecordName "${currentName}"
    if [ "${renameHomeDir}" = "1" ];then
        log "setting home directory to /Users/${newName}"
        $dsclBin . -change "/Users/${newName}" NFSHomeDirectory "${homeDir}" "/Users/${newName}"
        mv "${homeDir}" "/Users/${newName}"
    fi
fi

log "killing jamfHelper and loginwindow"

sudo killall jamfHelper

loggedInUser=$(stat -f%Su /dev/console)
ps -Ajc | grep loginwindow | grep "$loggedInUser" | grep -v grep | awk '{print $2}' | sudo xargs kill &
log "loginwindow restarted." &

#rm -fr $0
