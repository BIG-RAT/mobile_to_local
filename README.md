# Mobile to Local
Migrate mobile Active Directory account to a local account:

Wanted to create an easy to use method to migrate mobile accounts to local accounts.  One item in particular I wanted to address was ensuring a FileVault 2 enabled mobile account was migrated to a FileVault 2 enabled local account and have arrived at the following.

![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/app.png "Mobile to Local")

Download: [Mobile to Local](https://github.com/BIG-RAT/mobile_to_local/releases/download/current/Mobile.to.Local.app.zip)

The app should be launched with elevated privileges:

```sudo /path/to/Mobile\ to\ Local.app/Contents/MacOS/Mobile\ to\ Local```

If the app is launched with the -allowNewUser switch, the user is allowed to change their login name:

```sudo /path/to/Mobile\ to\ Local.app/Contents/MacOS/Mobile\ to\ Local -allowNewUser```

A notice will be displayed if the app is not launched with elevated privileges.
![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/privs.png "not elevated")

The password is verified during the process, if entered incorrectly the user will be alerted.
![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/pwd.png "password")

There is also a check to ensure the account is not already a local one.
![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/local.png "local")

If the user is allow to change their login name an alert will be given if the name is already taken.
![alt text](https://github.com/BIG-RAT/mobile_to_local/blob/master/mtl_images/exists.png "exists")

Attributes retained from the mobile account include:
* RealName
* NFSHomeDirectory
* UserShell
* JPEGPhoto
* GeneratedUID
* Mobile account shortname is added as an alias to the local account RecordName, if they differ.

The process is relatively quick, under 30 seconds, and logs to /var/log/jamf.log.  The resulting local account is FileVault 2 enabled and retains local group membership as a result of the GeneratedUID being transferred. 

Thanks for aiding in the project:
* @matthewsphillips
* @ryanslater_uk


