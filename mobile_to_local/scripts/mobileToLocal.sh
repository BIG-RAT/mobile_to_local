#!/bin/bash

## set -x

## passed variables
## $1 - new username
## $2 - password for user
## $3 - indicate if we're changing the home directory name; 0 - no change, 1 - change
## $4 - type of user to create; standard or admin
## $5 - whether or not to unbind - true or false
## $6 - whether or not the app runs silently - true or false
## $7 - how attributes are trimmed, remove only those defined (removeList) or keep only those defined (keepList) which is the default

logFile="/private/var/log/mobile.to.local.log"

log() {
    /bin/echo "$(date "+%a %b %d %H:%M:%S") $computerName ${currentName}[migrate]: $1" >> $logFile
}

dsclBin="/usr/bin/dscl"

## to list attributes
## $dsclBin -raw . -read /Users/${currentUser} | grep dsAttrType | awk -F":" '{ print $2 }'

## standard attributes for a local account - these will not be deleted from the mobile account
attribsToKeep="_writers_AvatarRepresentation\|_writers_hint\|_writers_inputSources\|_writers_jpegphoto\|_writers_passwd\|_writers_picture\|_writers_unlockOptions\|_writers_UserCertificate\|accountPolicyData\|AvatarRepresentation\|inputSources\|record_daemon_version\|unlockOptions\|AltSecurityIdentities\|AppleMetaNodeLocation\|AuthenticationAuthority\|GeneratedUID\|JPEGPhoto\|NFSHomeDirectory\|Password\|Picture\|PrimaryGroupID\|RealName\|RecordName\|RecordType\|UniqueID\|UserShell"

attribsToRemove=(_writers_LinkedIdentity account_instance cached_auth_policy cached_groups original_realname original_shell original_smb_home preserved_attributes AppleMetaRecordName CopyTimestamp EmailAddress FirstName JobTitle LastName MCXFlags MCXSettings OriginalAuthenticationAuthority OriginalNodeName PasswordPolicyOptions PhoneNumber PrimaryNTDomain SMBGroupRID SMBHome SMBHomeDrive SMBPasswordLastSet SMBPrimaryGroupSID SMBSID Street)

## in case the log file does not exist
if [ ! -f $logFile ];then
    /usr/bin/touch $logFile
    /bin/chmod 644 $logFile
fi


## grab the computer name to use in the log
computerName=$(scutil --get ComputerName)

## get logged in username and UniqueID (id can no longer be reset)
currentName=$( stat -f%Su /dev/console )
#oldID=$( $dsclBin . -read /Users/"$currentName" UniqueID | awk '/UniqueID: / {print $2}' )

## new username
newName="$1"

log """mobile to local parameters:
                        new username: $1
                        type of user to create: $4
                        unbind: $5
                        silent: $6
                        attribute mode: $7"""

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
log "current user: ${currentName} is a mobile user."

if [ $6 != "true" ];then
    ## verify we're either keeping the same username or new name doesn't exist
    nameCheck=$($dsclBin . -read "/Users/${newName}" RealName &> /dev/null;echo $?)
    if [ "$nameCheck" = "0" ] && [ ! "${newName}" = "${currentName}" ];then
        ## account already exists and belongs to a different user
        log "${newName} belongs to another user."
        exit 500
    fi
    password="$2"
fi

## get primary group id
groupId=$($dsclBin . read /Users/"${currentName}" PrimaryGroupID | awk '{print $2}')
staffAlias=$($dsclBin . list /Groups PrimaryGroupID | grep $groupId | awk '{print $1}')
if [ "$staffAlias" = "" ];then
    log "creating new group (staffAlias) to replace <domain>\DomainUsers"
    staffAlias="staffAlias"
    $dsclBin . create /Groups/$staffAlias
    $dsclBin . create /Groups/$staffAlias gid $groupId
    $dsclBin . create /Groups/$staffAlias RealName $staffAlias
else
    log "found existing local group ($staffAlias) to use for DomainUsers"
fi
log "adding built-in group staff to $staffAlias"
/usr/sbin/dseditgroup -o edit -a staff -t group $staffAlias

## renameHomeDir is 0 if we're not renaming the user home directory to the new name (if different the the existing) and 1 if we are
renameHomeDir="$3"
if [ "${renameHomeDir}" = "1" ];then
    log "Home directory will be renamed"
else
    log "Home directory will not be renamed"
fi

## set user type to create, if passed, to be either standard or admin.  If nothing is passed local will match mobile account
userType="$4"
if [ "${userType}" = "standard" ];then
    log "User will be migrated as a $userType user"
elif [ "${userType}" = "current" ];then
    log "User type will not be changed"
else
    log "User will be migrated as an $userType user"
fi

## set the unbind var; 'true' or 'false'
unbind="$5"
if [ "${unbind}" = "true" ];then
    log "machine will be unbound from Active Directory"
else
    log "no change to current bind status will be performed"
fi

## define icon location
theIcon="${BASH_SOURCE%/*}/../MigrateAsst.png"

## see if account is FileVault enabled
FileVaultUserCheck=$(fdesetup list | grep -w "${currentName}")
if [ "${FileVaultUserCheck}" != "" ];then
    log "${currentName} is a FileVault enabled user"
else
    log "${currentName} is not a FileVault enabled user"
fi

#    ## capture account photo to migrate to the new account
#    JpegPhoto=$($dsclBin . -read "/Users/$currentName" JPEGPhoto > "/tmp/$currentName.hex"
#    xxd -plain -revert "/tmp/$currentName.hex" > "/tmp/$currentName.png")

if [ "$unbind" == "true" ];then
## unbind
    log "performing machine unbind"
    /usr/sbin/dsconfigad -remove -force -username "$currentName" -password "${password}"
    log "result of unbind operation: $?"
    /bin/rm "/Library/Preferences/OpenDirectory/Configurations/Active Directory/*.plist"
fi

## remove .account file if present
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

## find first available id
## can no longer reset id
#newID="501"
#allUsers=$($dsclBin . -list /Users UniqueID | awk '{ print $2 }')
#isUnique=$(echo "$allUsers" | grep "^$newID$")
#while [ "$isUnique" != "" ];do
#    ((newID++))
#    isUnique=$(echo "$allUsers" | grep "^$newID$")
#done
#echo "$(date "+%a %b %d %H:%M:%S") $computerName ${currentName}[migrate]: new id: $newID" >> /var/log/jamf.log

## export updated AuthenticationAuthority for the account
log "$dsclBin . -read /Users/${currentName} AuthenticationAuthority"
## localAuthenticationAuthority=$($dsclBin . -read /Users/"${currentName}" AuthenticationAuthority)
log "AuthenticationAuthority for local account:"
localAuthenticationAuthority=$($dsclBin -plist . -read /Users/"${currentName}" AuthenticationAuthority)
log "${localAuthenticationAuthority}"

log "------------- Start deleting attributes --------------"
log "    delete using $7"
## remove attributes from mobile account - start
if [[ $7 == "removelist" ]];then
    for theAttribute in "${attribsToRemove[@]}";do
        log "deleting attribute: $theAttribute"
        if [[ $theAttribute == "AppleMetaRecordName" || $theAttribute == "PrimaryNTDomain" ]];then
            $dsclBin -raw . -delete "/Users/${currentName}" "dsAttrTypeStandard:"$theAttribute 2>/dev/null
        else
            $dsclBin . -delete "/Users/${currentName}" $theAttribute 2>/dev/null
        fi
        ##
    done
else
while read theAttribute;do
    log "deleting attribute: $theAttribute"
    $dsclBin -raw . -delete "/Users/${currentName}" $theAttribute 2>/dev/null
#    #    echo $?
done << EOL
$($dsclBin -raw . -read "/Users/${currentName}" | grep dsAttrType | awk -F":" '{print $1 ":" $2}' | grep -v -w "${attribsToKeep}")
EOL
fi
## remove attributes from mobile account - end
log "------------ Finished deleting attributes ------------"

#### for testing, to pause the script ####
#touch /Users/Shared/pause.txt
#while [ -f /Users/Shared/pause.txt ];do
#    sleep 10
#done

## ensure proper group on home directory
## skipping the change of owner permissions on the user folder to avoide PPPC prompts for contacts and calendars??
## handle later, fixing permissions on all files/folders
#homeDir=$($dsclBin . -read /Users/"${currentName}" NFSHomeDirectory | awk -F": " '{ print $2 }')
#log "Setting group and permissions for ${homeDir}"
#    log "chown -Rf :staff ${homeDir}"
#    result=$(chown -Rf ":staff" "${homeDir}" &> /dev/null;echo "$?")
#if [ "$result" = "0" ];then
#    log "updated group for home directory"
#else
#    log "failed to updated group for home directory"
#fi
#
### add user to staff group
#result=$(/usr/sbin/dseditgroup -o edit -n /Local/Default -a "${currentName}" -t user staff;echo "$?")
#if [ "$result" = "0" ];then
#    log "${currentName} was added to the staff group"
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
    ## get current home directory
    homeDir=$($dsclBin . -read /Users/"${currentName}" NFSHomeDirectory | awk -F": " '{ print $2 }')
    log "Current home directory: ${homeDir}"
    
    log "Change in login name has been requested"
    log "Changing the Record name from ${currentName} to ${newName}"
    $dsclBin . -change "/Users/${currentName}" RecordName "${currentName}" "${newName}"
    log "adding alias for old username: ${currentName}"
    $dsclBin . -append "/Users/${newName}" RecordName "${currentName}"
    if [ "${renameHomeDir}" = "1" ];then
        log "Moving (renaming) current home directory ${homeDir} to /Users/${newName}"
        /bin/mv "${homeDir}" "/Users/${newName}"
        
        log "setting home directory (NFSHomeDirectory) to /Users/${newName}"
        log "$dsclBin -u ${newName} -P '********' . -change \"/Users/${newName}\" NFSHomeDirectory \"${homeDir}\" \"/Users/${newName}\""
        $dsclBin -u "${newName}" -P \'"${password}"\' . -change "/Users/${newName}" NFSHomeDirectory "${homeDir}" "/Users/${newName}"
    fi
fi

## update user id
#log "Changing UniqueID from $oldID to $newID"
#log "$dsclBin -u \"${newName}\" -P '*******' . -change \"/Users/${newName}\" UniqueID $oldID $newID"
#$dsclBin -u "${newName}" -P \'"${password}"\' . -change "/Users/${newName}" UniqueID $oldID $newID

## fix permissions for all items owned by the previous name/id
#log "Fix permissions for new UniqueID"
#find / -uid $oldID -exec chown -h $newID {} \; 2>/dev/null

if [ $6 != "true" ];then
    loggedInUser=$(stat -f%Su /dev/console)
    ps -Ajc | grep loginwindow | grep "$loggedInUser" | grep -v grep | awk '{print $2}' | sudo xargs kill &
    log "loginwindow restarted." &
fi

#rm -fr $0
