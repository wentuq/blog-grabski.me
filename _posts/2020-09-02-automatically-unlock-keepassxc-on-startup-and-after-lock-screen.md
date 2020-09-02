---
layout: post
title: Automatically unlock KeepassXC on startup and after lock screen
categories: tech, linux
date: 2020-09-02T19:10:45.766Z
thumbnail: /assets/uploads/keepassxc-lock.png
---
I will be using Ubuntu 20.04 and KeepassXC 2.6.1 but this guide should work for any GNOME desktop.

To securely store KeepassXC main database password we will use `secret-tool` from package `libsecret-tools`. Using this tool we make sure that we don't store our password for KeepassXC in plaintext somewhere in our system.

To lock/unlock KeepassXC we will communicate through [d-bus](https://en.wikipedia.org/wiki/D-Bus).
For KDE it's necessary to modify the script slightly and use `qdbus` instead.

There is CLI tool `keepassxc-cli` installed along with keepassxc but it works independently, so if we have opened db in keepassxc we cannot close it using keepassx-cli.

OK, enough talking, let's do the job.

## Install libsecret-tools

Execute in terminal:
`$ apt install libsecret-tools`

## Securely store KeepassXC database password

Attention! Change angle brackets accordingly to your setup.

Based on this gist[^1] execute:
```
$secret-tool store --label="KeePass <database_name>" keepass <database_name>
```

## Lock database when session is locked or lid is closed

It's easy to do in UI.

![KeepassXC security settings](/assets/uploads/keepassxc-settings.png)

Tools -> Settings -> Security -> Lock database when session is locked or lid is closed


## Create scripts for startup, lock/unlock of KeepassXC

We will create a few scripts to easily do the job. All of the scripts has to be in environmental `$PATH` in my case it is `~/bin`.

### keepassxc-unlock

Attention! Change angle brackets `<dabase_name>`, `<path-to-your-db>`, `<path-to your-keyfile>` accordingly.

Content of `keepassxc-unlock` - script gets a db password from secret-tool and using d-bus we speak to keepassxc to unlock db.

```
#!/bin/bash
# Get password using secret-tool and unlock keepassxc
tmp_passwd=$(secret-tool lookup keepass <dabase_name>)
database='<path-to-your-db>'
keyfile='<path-to your-keyfile>'
dbus-send --print-reply --dest=org.keepassxc.KeePassXC.MainWindow /keepassxc org.keepassxc.MainWindow.openDatabase \
string:$database string:$tmp_passwd string:$keyfile
```

### keepassxc-lock

Content of `keepassxc-lock` - we just send a message through d-bus to lock db.
```
#!/bin/bash
dbus-send --print-reply --dest=org.keepassxc.KeePassXC.MainWindow /keepassxc org.keepassxc.MainWindow.lockAllDatabases
```

### keepassxc-startup

Content of `keepassxc-startup` - keepassxc has option to startup automatically, but we will take care of it on our own. Otherwise it might happen that we will try to unlock keepassxc before it's' up and running.

```
#!/bin/bash
keepassxc&
sleep 1
keepassxc-unlock
```

### keepassxc-watch

Content of `keepassxc-watch` - this script looks for d-bus message that the screensaver/session is unlocked, then we unlock password manager.

```
#!/bin/bash
# KeepassXC watch for logout and unlock a database

dbus-monitor --session "type=signal,interface=org.gnome.ScreenSaver" | 
  while read MSG; do
    LOCK_STAT=`echo $MSG | grep boolean | awk '{print $2}'`
    if [[ "$LOCK_STAT" == "false" ]]; then
        keepassxc-unlock
    fi
  done
```

All of the files needs to be executable, so in our scripts directory we do:
```
chmod +x ./keepassxc-lock ./keepassxc-startup ./keepassxc-unlock ./keepassxc-watch
```

Now you should try to run the scripts and check if everything is working as supposed

## Add scripts to startup

We will add two of our scripts to run in startup: 

* `keepassxc-startup` - start up keepassxc and unlocks db
* `keepassxc-watch` - watch if we unlocked session, if so we unlock keepassxc

There is two methods, by GUI, using  `Startup Applications` or using terminal.

Let's create two .desktop files in `~/.config/autostart`

Content of `keepassxc-startup.desktop`:

```
[Desktop Entry]
Type=Application
Exec=/home/grabek/bin/keepassxc-startup
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2 
Hidden=false
NoDisplay=false
Name=keepass
Comment[en_GB]=Lanuch unlocked keepass
Comment=Lanuch unlocked keepass
Name[en_GB]=keepassxc-startup
```

Content of `keepassxc-watch.desktop`:

```
[Desktop Entry]
Type=Application
Exec=/home/grabek/bin/keepassxc-watch
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name[en_GB]=keepassxc-watch
Name=KeepassXC watch for logout and unlock
Comment[en_GB]=KeepassXC watch for logout and unlock
Comment=KeepassXC watch for logout and unlock
```


## Create a desktop launchers for more convenience

We will also create two desktop launchers for easy lock/unlock KeepassXC in GNOME.

Let's create two files in `~/.local/share/applications

Content of `keepassxc-lock.desktop`:

```
[Desktop Entry]
Name=KeePassXC-lock
GenericName=Password Manager
Comment=Secure way to lock KeepassXC
Exec=keepassxc-lock
Icon=keepassxc
StartupNotify=false
Terminal=false
Type=Application
Version=1.0
Categories=Utility;Security;Qt;
MimeType=application/x-keepass2;
```

Content of `keepassxc-unlock.desktop`:
```
[Desktop Entry]
Name=KeePassXC-unlock
GenericName=Password Manager
Comment=Secure way to unlock KeepassXC
Exec=keepassxc-unlock
Icon=keepassxc
StartupNotify=false
Terminal=false
Type=Application
Version=1.0
Categories=Utility;Security;Qt;
MimeType=application/x-keepass2;
```

From now on, we can just do `⊞ Win` and then starts typing lock or unlock

![KeepassXC security settings](/assets/uploads/keepassxc-lock.png)


## Security concerns

**In this solution we trade security for easiness and simplicity.**

It's easy to get our password in plaintext while we are logged in, just type in terminal: `$ secret-tool lookup keepassxc passwords` - BAM! our super-secure password in plaintext.

To delete our password stored in secret-tool we execute `secret-tool clear keepass <dabase_name>`

You can see more records in GNOME keyring using [Seahorse](https://wiki.gnome.org/Apps/Seahorse).
 
## Reference

[^1]: [Automatically unlock KeePass database with GNOME Keyring](https://gist.github.com/dAnjou/b99f55de34b90246f381e71e3c8f9262)