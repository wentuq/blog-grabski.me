---
layout: post
title:  "How to properly setup secure DNS using dnscrypt-proxy on Ubuntu"
date:   2020-07-09 01:03:00 +0200
categories: jekyll update
---

## Introduction

We will install, configure and autoupdate of dnscrypt-proxy, which will be set as our *only* resolver in the system. Configure special instance of Chrome to connect to captive portals - which are unsafe and impossible to access through dnscrypt-proxy. It will be also helpfull when we fail to configure dnscrypt-proxy properly.

Firefox has an option to use ESNI[^1] but only if DOH[^2] is enabled as well in Firefox, we would like a system wide solution, that's why we will setup local doh server using dnscrypt-proxy. We will also install locally trusted certificates to make local doh server *https* available.


## Captive portal

We are going to install separate instance of Google Chrome used only for logging into captive portals.

First we need to export paths to bash/zsh (`~/.bashrc` or `~/.zshrc`).
```
#go runtime
export GOPATH=$HOME/go
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
```

Then follow the instructions
https://github.com/FiloSottile/captive-browser

We should have binary file in `~/go/bin/captive-browser` and we are gonna use a captive portal whenever we are connecting to the airport paywall network.

### Extra (create a .desktop file)

We will create a `.desktop` file to *easily* run captive-browser from GNOME search bar

`captive-browser.desktop` content:

```
[Desktop Entry]
Version=1.0
Name=Captive Browser
GenericName=Non Safe Web Browser
Exec=captive-browser
Terminal=false
Type=Application
Icon=google-chrome
StartupNotify=true
```
We will put the file inside `$HOME/.local/share/applications/`

##### Digression

When we search for the file in GNOME, there's a chance that we will not find `Captive Browser`. In that case we will have to give a full hard path to captive-browser for ex. `/home/yourhomedir/go/bin/captive-browser`
From what I found it's all because XDG_DATA_DIRS, but even when I added path `export XDG_DATA_DIRS=$XDG_DATA_DIRS:$HOME/go/bin` it was finding it GNOME but could run it. Somehow when I symlinked `ln -s $HOME/go/bin/captive-browser $HOME/bin` it works even though `$HOME/bin` is not in `$XDG_DATA_DIRS`. Suuper weird.

## Local certificates for localhost

https://github.com/FiloSottile/mkcert - mkcert is a simple tool for making locally-trusted development certificates. It requires no configuration. It is used to connect to our localhost by https
```
go get -u github.com/FiloSottile/mkcert
```
Now we should have mkcert executable in `~/go/bin`

Execute
```
cd ~/go/bin
./mkcert -install -key-file localhost-key.pem -cert-file localhost.pem localhost 127.0.0.1
```
We just installed our certificates. We should have generated two files `localhost-key.pem` and `localhost.pem` in `~/go/bin`. We are going to need them later.


### Side-note: to uninstall
```
./mkcert -uninstall -key-file localhost-key.pem -cert-file localhost.pem localhost 127.0.0.1
```

## dnscrypt-proxy[^3]

Version in the ubuntu repository is old and there are some configuration gimmicks. That's why I recommend to install it from the source

### Get and install dnscrypt-proxy

Download latest release from [github](https://github.com/DNSCrypt/dnscrypt-proxy/releases).  `dnscrypt-proxy-linux_x86_64-*.tar.gz` This is the one most people want.

Execute:
```
tar xvzf ./dnscrypt-proxy-linux_x86_64-*.tar.gz
cd ./dnscrypt-proxy-linux_x86_64-*/linux-x86_64
sudo mkdir /usr/local/dnscrypt-proxy
sudo mv ./dnscrypt-proxy /usr/local/dnscrypt-proxy
sudo ln -s /usr/local/dnscrypt-proxy/dnscrypt-proxy /usr/local/bin
# We are going to delete self signed certficate
# because we are going to use two certs that
# we had generated before which doesn't rise any error in browsers
sudo rm ./localhost.pem
sudo mkdir /etc/dnscrypt-proxy
sudo cp * /etc/dnscrypt-proxy
```

Now it's time to move our previously generated ceritficates.
```
cd ~/go/bin
mv ./localhost.pem /etc/dnscrypt-proxy
mv ./localhost-key.pem /etc/dnscrypt-proxy
```

#### Configure dnscrypt-proxy

Here is mine `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` config file - [link to gist](https://gist.github.com/wentuq/5e95a7612111d0ef409d4e31e688abe3)

Check especially the line that starts with `server_names` - those are the servers we want to connect, we can leave that empty, dnscrypt will find the fastest server.

From documentation:
```
## If this line is commented, all registered servers matching the require_* filters
## will be used.
```

We can choose which protocol and what server we want to connect here: https://dnscrypt.info/public-servers


### Switch off current DNS resolver
#### From now on we can have no internet connection, until we setup properly dnscrypt-proxy

Check what is listening on port 53
`ss -lp 'sport = :domain'` or command `sudo netstat -lnptu`

Now we are going to disable system resolver:
```
systemctl stop systemd-resolved
systemctl disable systemd-resolved
```

Remove dnsmasq - it is no longer needed because all functions are included in dnscrypt-proxy.
`sudo apt remove --purge dnsmasq`

To disable dnsmasq for NetworkManager, make the `/etc/NetworkManager/NetworkManager.conf` mine looks like this:
```
[main]
plugins=ifupdown,keyfile
# Stops overwriting /etc/resolv.conf by NetworkManager
# because we use dnscrypt-proxy
dns=none
# Need to comment this line because of use dnscrypt-proxy
#dns=dnsmasq

[ifupdown]
managed=false

[device]
# Random mac address
# should be already default
wifi.scan-rand-mac-address=yes

```

### Setting up /etc/resolv.conf


Now the most problematic issue. Because we want to make sure that no matter which connection we are going to use, WLAN (different networks) or LAN we always want to have dnscrypt-proxy working. The trouble is that many system apps/daemons are trying to modify `/etc/resolv.conf`

For example:
* resolvconf
* systemd-resolved - [**!four!** modes of handling](https://www.freedesktop.org/software/systemd/man/systemd-resolved.service.html) `/etc/resolv.conf`
* dhcpd
* NetworkManager

In short, it's overcomplicated. For now, we disabled systemd-resolved, and NetworkManager so they are out of the game. There are many ways for this solution, and personally I'm not completly satisfied from any options below.

#### Option 1 (preffered)

Remove resolvconf and lock /etc/resolv.conf from modyfing (by anything that is trying to alter it) by setting a file atrribute

```
apt-get remove resolvconf
cp /etc/resolv.conf /etc/resolv.conf.backup
rm -f /etc/resolv.conf
```
And create a new /etc/resolv.conf.override file with the following content. That will be our helper file for [other scripts](#fast-way-to-toggle-dnscrypt-offon)
```
# Created for dnscrypt-proxy
# This is a content of /etc/resolv.conf.override
nameserver 127.0.0.1
options edns0
```
Then, let's just copy it on right place

```
cp /etc/resolv.conf.override /etc/resolv.conf
```

##### Extra step

If any other program, service, daemon, you name it, changes `/etc/resolv.conf`. Let's set a sticky bit Immutable on file by command:
```
chattr +i /etc/resolv.conf
```


Side note: To unlock it:
```
chattr -i /etc/resolv.conf
```

#### Option 2

We will use resolvconf and put a trigger script for NetworkManager to use our configuration

Firstly we need to make sure that `resolvconf` is installed.

Now we are going to create file `/etc/resolv.conf.override`

```
# Created for dnscrypt-proxy
# This is a content of /etc/resolv.conf.override
nameserver 127.0.0.1
options edns0
```

then we are going to create a script `/etc/NetworkManager/dispatcher.d/20-resolv-conf-override` for NetworkManager with following content
```
#!/bin/sh
cp -f /etc/resolv.conf.override /run/resolvconf/resolv.conf
```
and then we're going to create a symlink for it to execute
```
cd /etc/NetworkManager/dispatcher.d 
ln -s /etc/NetworkManager/dispatcher.d/20-resolv-conf-override pre-up.d/
```
From now, whenever we are connecting through NetworkManger, script is going to override `/etc/resolv.conf` with our own configuration using resolvconf

#### Option 3 - Always use systemd-resolved (127.0.0.53)
##### Rest of article doesn't comply with Option 3

Modify file `/etc/systemd/resolved.conf`
In section `[Resolve]` add:
```
DNS=127.0.0.1
```

then we are going to symlink our systemd-resolved. This is mode 1 in systemd-resolved documentation

```
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

### Setup dnscrypt-proxy

Check if everything is working

```
cd /etc/dnscrypt-proxy
dnscrypt-proxy -resolve example.com
```

Check if DNS are resolved
```
$ dig dnscrypt.info | grep SERVER
;; SERVER: 127.0.0.1#53(127.0.0.1)
```

If we have this, we are fine to go further

### Install dnscrypt-proxy as service (daemon)

Run the command
```
cd /etc/dnscrypt-proxy
sudo dnscrypt-proxy -service install
```

To uninstall
```
sudo dnscrypt-proxy -service uninstall
```

Now that it's installed, it can be started:
```
cd /etc/dnscrypt-proxy
dnscrypt-proxy -service start
```
Done!

## Setup Firefox TTR

Firefox has an option to use ESNI[^1] bot only if built-in Firefox DOH[^2] is also switched on. That's why we need to make local DOH server. Let's instruct Firefox to use our local DOH server.

### about:config
To edit hidden options in Firefox, type `about:config` in address bar.

[Learn more about TRR preferences](https://bagder.github.io/TRRprefs/), [here also](https://wiki.mozilla.org/Trusted_Recursive_Resolver).

```
network.security.esni.enabled, true
network.trr.bootstrapAddress, 127.0.0.1
network.trr.custom_uri, https://127.0.0.1:3000/dns-query
network.trr.early-AAAA, true
network.trr.mode, 3
network.trr.uri, https://127.0.0.1:3000/dns-query
network.trr.wait-for-A-and-AAAA, false
network.trr.wait-for-portal, false

```

We are going to disable the captive portal too. I don't know why, but just disabling captive portal still connects to `https://https//detectportal.firefox.com/success.txt ` because of that we will change those 3 options:
```
captivedetect.canonicalURL, ""
network.captive-portal-service.enabled, false
network.connectivity-service.enabled, false
```

Restart browser and check if everything is correct. In Firefox address bar type `about:networking` Go to tab: DNS. Check TRR values. They all need to be set to true.


## Final check

[Check if ESNI is working](https://www.cloudflare.com/ssl/encrypted-sni/) - last three checks should be green.

[Check DNS leaks](https://www.dnsleaktest.com/)


## Automatic updates of dnscrypt-proxy

Following [automatic update guide](https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Updates)


Inside folder `/usr/local/dnscrypt-proxy` create a file named `dnscrypt-proxy-update.sh` with following content - [see gist](https://gist.github.com/wentuq/e19611f7ac3114c89ab4cdf88e69f314)

Then execute
```
cd /usr/local/dnscrypt-proxy
sudo chmod +x ./dnscrypt-proxy-update.sh
sudo ln -s /usr/local/dnscrypt-proxy/dnscrypt-proxy-update.sh /usr/local/bin/dnscrypt-proxy-update
```

Check if everything is working
```
./dnscrypt-proxy-update.sh
```

Now we are going to add this to cron to run it regularly.
```
sudo crontab -e
```
add following line
```
0 */12 * * * /usr/local/dnscrypt-proxy/dnscrypt-proxy-update.sh
```
[crontab guru](https://crontab.guru/#0_*/12_*_*_*) says our script is going to be executed “At minute 0 past every 12th hour.”


## Fast way to toggle dnscrypt off/on 
### Only for Option 1 install of dnscrypt-proxy

### toggle off dnscrypt-proxy - promiscous_dns
Inside `~/bin` we will create a file `promiscous_dns`
with following content
```
#!/bin/sh

text="# Created by ~/bin/promiscous_dns"
cp -f /var/run/NetworkManager/resolv.conf /etc/resolv.conf
sed -i "1i$text" /etc/resolv.conf
```

### To toggle on dnscrypt-proxy - secure_dns
Inside `~/bin` we will create a file `secure_dns` with following content
```
#!/bin/sh

text="# Created by ~/bin/secure_dns"
cp -f /etc/resolv.conf.override /etc/resolv.conf
sed -i "1i$text" /etc/resolv.conf
```


## VPN
If VPN is being used, should we use dnscrypt-proxy or not? I think we should disable it. The question is what's really happening when we connect through VPN? Are our queries sent by dnscrypt-proxy or VPN?

While we have our `/etc/resolv.conf` hardcoded, and NetworkManger is instructed not to modify resolv.conf, we should replace our DNS for VPN ones, after connecting to VPN with command `sudo ~/bin/promiscous_dns`
or do it automatically by adding a script to NetworkManager

### Running a script after connection to VPN

Script will automatically change for VPN DNS after connecting:

Let's create a script in `/etc/NetworkManager/dispatcher.d' named `99-vpn-resolve`
```
#!/bin/sh

text='# Modified by /etc/NetworkManager/dispatcher.d/99-vpn-resolve'

if [ "$2" = "vpn-up" ]; then
        cp -f /var/run/NetworkManager/resolv.conf  /etc/resolv.conf
        # Adding first line
        sed -i "1i$text" /etc/resolv.conf
fi

if [ "$2" = "vpn-down" ]; then
        cp -f /etc/resolv.conf.override /etc/resolv.conf
        # Adding first line
        sed -i "1i$text" /etc/resolv.conf
fi
```

Last thing, we have to make it executable `chmod +x /etc/NetworkManager/dispatcher.d/99-vpn-resolve`

It should work from now on. We can check it by running VPN and test by https://dnsleaktest.com/

#### Extra: user.js and reload of Firefox with proper settings

Because Firefox doesn't care about `/etc/resolv.conf` while we use ESNI and DOH in Firefox it's easy to forget that Firefox still uses own settings. When we connect to VPN, we will switch off dnscrypt-proxy and restart Firefox.
Let's create two files in your Firefox profile:

Content of `user.js.secure`
```
// Preferences for TTR switched ON
user_pref("network.security.esni.enabled", true);
// boostrapAddress no longer necessary
// user_pref("network.trr.bootstrapAddress", "127.0.0.1");
user_pref("network.trr.custom_uri", "https://127.0.0.1:3000/dns-query");
user_pref("network.trr.early-AAAA", true);
user_pref("network.trr.mode", 3);
user_pref("network.trr.uri", "https://127.0.0.1:3000/dns-query");
user_pref("network.trr.wait-for-A-and-AAAA", false);
user_pref("network.trr.wait-for-portal", false);
// Disable captive portal
user_pref("network.captive-portal-service.enabled", false);
user_pref("captivedetect.canonicalURL", "");
user_pref("network.connectivity-service.enabled", false);
```

Content of `user.js.unsecure`:
```
// We just need to reset this option
network.trr.mode, 0
```

Content of our modified `/etc/NetworkManager/dispatcher.d/99-vpn-resolve`:
Just modify path to Firefox profile
```
#!/bin/sh

firefoxpath='YOUR-FIREFOX-PROFILE-PATH'
text='# Modified by /etc/NetworkManager/dispatcher.d/99-vpn-resolve'

if [ "$2" = "vpn-up" ]; then
	cp -f /var/run/NetworkManager/resolv.conf  /etc/resolv.conf
	# Adding first line
	sed -i "1i$text" /etc/resolv.conf
	# Stop dnscrypt-proxy
	dnscrypt-proxy -service stop
	# Reset settings and close Firefox
	cp "$firefoxpath"user.js.unsecure "$firefoxpath"user.js
	pgrep firefox
	if [ $? -eq 0 ]; then
		pkill -SIGTERM firefox
	fi
	# TODO: how to run it again?
fi

if [ "$2" = "vpn-down" ]; then
	cp -f /etc/resolv.conf.override /etc/resolv.conf
	# Adding first line
	sed -i "1i$text" /etc/resolv.conf
	# Start dnscrypt-proxy
	dnscrypt-proxy -config /etc/dnscrypt-proxy -service stop
	# Reset settings and close Firefox
	pkill firefox
	cp "$firefoxpath"user.js.secure "$firefoxpath"user.js
	pgrep firefox
	if [ $? -eq 0 ]; then
		pkill -SIGTERM firefox
	fi
	# TODO: how to run it again?
fi
```


## TODO

* Check by wireshark that all DNS queries are encrypted - basically it's true, because if we stop dnscrypt-proxy daemon we cannot resolve any address, but it's worth checking anyway, for working ESNI for example


## Further reading:

[^1]: [ESNI](https://en.wikipedia.org/wiki/Server_Name_Indication#Encrypted_SNI_(ESNI)) - Encrypted Server Name Indication - in future is going to be replaced by ECH, Firefox and cloudflare implements [v1 of internet draft](https://tools.ietf.org/html/draft-ietf-tls-esni-01) more: on [cloudflare](https://www.cloudflare.com/ssl/encrypted-sni/) and [firefox](https://blog.mozilla.org/security/2018/10/18/encrypted-sni-comes-to-firefox-nightly/), [check if you encrypt SNI](https://www.cloudflare.com/ssl/encrypted-sni/)
[^2]: [DoH](https://en.wikipedia.org/wiki/DNS_over_HTTPS) - DNS over HTTPS, one of the solutions to encrypt DNS, other is DoT (DNS over TLS) which is internet standards but it's easier to block by internet providers, 
[^3]: [dnscrypt-proxy](https://github.com/DNSCrypt/dnscrypt-proxy) there are few installation guides, ex. for [Linux](https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Installation-linux) and for [Ubuntu](https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Installation-on-Debian-and-Ubuntu), for Ubuntu I still recommend to follow general linux guide.