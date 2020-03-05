# Mobile to Local
Migrate mobile Active Directory account to a local account:

Wanted to create an easy to use method to migrate mobile accounts to local accounts.  One item in particular I wanted to address was ensuring a FileVault 2 enabled mobile account was migrated to a FileVault 2 enabled local account and have arrived at the following.

![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/main.png "Mobile to Local")

Download: [Mobile to Local](https://github.com/BIG-RAT/mobile_to_local/releases/download/current/Mobile.to.Local_v2.0.0.zip)

The app should be launched with elevated privileges:

```sudo /path/to/Mobile\ to\ Local.app/Contents/MacOS/Mobile\ to\ Local```


A notice will be displayed if the app is not launched with elevated privileges.
![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/privs.png "not elevated")

The password is verified during the process, if entered incorrectly the user will be alerted.
![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/password.png "password")

There is also a check to ensure the account is not already a local one.
![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/localAccount.png "local")

If the user is allowed to change their login name an alert will be given if the name is already taken.
![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/exists.png "exists")

Attributes not needed for the local account are removed, currently these are the following:

* _writers_LinkedIdentity
* account_instance
* cached_auth_policy
* cached_groups
* original_realname
* original_shell
* original_smb_home
* preserved_attributes
* AppleMetaRecordName
* CopyTimestamp
* EMailAddress
* FirstName
* JobTitle
* LastName
* MCXFlags
* MCXSettings
* OriginalAuthenticationAuthority
* OriginalNodeName
* PasswordPolicyOptions
* PhoneNumber
* PrimaryNTDomain
* SMBGroupRID
* SMBHome
* SMBHomeDrive
* SMBPasswordLastSet
* SMBPrimaryGroupSID
* SMBSID
* Street

* AuthenticationAuthority has LocalCachedUser and Kerberosv5 settings removed

Mobile account shortname is added as an alias to the local account RecordName, if they differ.


The process is relatively quick, under 30 seconds, and logs to /var/log/jamf.log.  The resulting local account is FileVault 2 enabled (if enabled to begin with) and retains local group membership.

The local account retains the uniqueID of the mobile account, this removes the need to reset permissions.  Group permissions are not updated on the users folder, this is to avoid PPPC issues.

To allow the user to change their login name launch the app with the -allowNewUsername switch:

```sudo /path/to/Mobile\ to\ Local.app/Contents/MacOS/Mobile\ to\ Local -allowNewUsername true```

![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/nameChange.png "nameChange")

To specify the type of local account to create use the -userType switch:

```sudo /path/to/Mobile\ to\ Local.app/Contents/MacOS/Mobile\ to\ Local -userType admin```

The switches can be used together (order doesn't matter):

```sudo /path/to/Mobile\ to\ Local.app/Contents/MacOS/Mobile\ to\ Local -allowNewUsername true -userType admin```


Thanks for aiding in the project:
* @matthewsphillips
* @ryanslater_uk


