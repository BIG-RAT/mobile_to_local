#!/bin/bash

## set -x

## passed variables
## $1 - new username
## $2 - type of user to create; standard or admin
## $3 - whether or not to unbind - true or false
## $4 - whether or not the app runs silently - true or false
## $5 - new full name

logFile="/private/var/log/mobile.to.local.log"
dsclBin="/usr/bin/dscl"

log() {
    /bin/echo "$(date "+%a %b %d %H:%M:%S") $computerName ${currentName}[migrate]: $1" >> $logFile
}

## to list attributes
## $dsclBin -raw . -read /Users/${currentUser} | grep dsAttrType | awk -F":" '{ print $2 }'

## OriginalAuthenticationAuthority -keep for testing

## standard attributes for a local account - these will not be deleted from the mobile account
attribsToKeep="_writers_AvatarRepresentation\|_writers_hint\|_writers_inputSources\|_writers_jpegphoto\|_writers_passwd\|_writers_picture\|_writers_unlockOptions\|_writers_UserCertificate\|accountPolicyData\|AvatarRepresentation\|inputSources\|record_daemon_version\|unlockOptions\|AltSecurityIdentities\|AppleMetaNodeLocation\|AuthenticationAuthority\|GeneratedUID\|JPEGPhoto\|NFSHomeDirectory\|Password\|Picture\|PrimaryGroupID\|RealName\|RecordName\|RecordType\|UniqueID\|UserShell"

attribsToRemove=(_writers_LinkedIdentity account_instance cached_auth_policy cached_groups original_realname original_shell original_smb_home preserved_attributes AppleMetaRecordName CopyTimestamp EmailAddress FirstName JobTitle LastName MCXFlags MCXSettings OriginalAuthenticationAuthority OriginalNodeName PasswordPolicyOptions PhoneNumber PrimaryNTDomain SMBGroupRID SMBHome SMBHomeDrive SMBPasswordLastSet SMBPrimaryGroupSID SMBSID Street)

## grab the computer name to use in the log
computerName=$(scutil --get ComputerName)

## get logged in username and UniqueID (id can no longer be reset)
currentName="$(stat -f%Su /dev/console)"

newName="$1"
newFullname="$5"
userType="$2"

log """mobile to local parameters:
                        new username: $1
                        new fullname: $5
                        type of user to create: $2
                        unbind: $3
                        silent: $4"""

## get primary group id
groupId=$($dsclBin . read /Users/"${currentName}" PrimaryGroupID | awk '{print $2}')
staffAlias=$($dsclBin . list /Groups PrimaryGroupID | grep "\b$groupId\b" | awk '{print $1}')
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

## set the unbind var; 'true' or 'false'
unbind="$3"
if [ "${unbind}" = "true" ];then
    log "machine will be unbound from Active Directory"
else
    log "no change to current bind status will be performed"
fi

## see if account is FileVault enabled
FileVaultUserCheck=$(fdesetup list | grep -w "${currentName}")
if [ "${FileVaultUserCheck}" != "" ];then
    log "${currentName} is a FileVault enabled user"
else
    log "${currentName} is not a FileVault enabled user"
fi

if [ "$unbind" == "true" ];then
## unbind
    log "performing machine unbind"
    /usr/sbin/dsconfigad -remove -force -username "$currentName" -password "123456"
    log "result of unbind operation: $?"
    /bin/rm "/Library/Preferences/OpenDirectory/Configurations/Active Directory/*.plist"
fi

## remove .account file if present
/bin/rm -f "/Users/${currentName}/.account" || true

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

## add to the admins group, if appropriate
if [ "$userType" = "admin" ];then
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
    homeDir=$($dsclBin . -read "/Users/${currentName}" NFSHomeDirectory | awk -F": " '{ print $2 }')
    log "Current home directory: ${homeDir}"
    
    log "Change in login name has been requested"
    log "Changing the Record name from ${currentName} to ${newName}"
    $dsclBin . -change "/Users/${currentName}" RecordName "${currentName}" "${newName}"
    log "adding alias for old username: ${currentName}"
    $dsclBin . -append "/Users/${newName}" RecordName "${currentName}"
fi
