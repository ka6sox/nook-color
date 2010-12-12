#!/bin/sh

# optware-bootstrap.sh
# version 1.1.1
#
# Script to automate the process of permanently enabling Linux access
# based on optware-bootstrap-manual.sh by Jack Cuyler (JackieRipper)
#
# Features:
# 1.  Mounts the root file system read-write
# 2.  Creates and mounts /opt, and updates /etc/fstab
# 3.  Downloads and installs ipkg-opt
# 4.  Configures /opt/etc/ipkg/optware.conf
# 5.  Creates /etc/profile.d/optware
# 6.  Updates the Optware package database
# 7.  Create an unprivledged user
# 8.  Installs sudo
# 9.  Configures sudo privs for the user created above
# 10. Installs openssh and openssh-sftp-server
# 11. Patches ramdisk to configure environment on boot on nook color

### VARIABLES: GENERAL

MYUSER=""

LOG=/data/tmp/optware-bootstrap.log
PATH="/system/xbin:/opt/sbin:/opt/bin:/opt/local/bin:/sbin:/system/sbin:/system/bin"
LD_LIBRARY_PATH="/opt/lib:/system/lib"

ARCH=armv7l
FEED_URL="http://ipkg.nslu2-linux.org/feeds/optware"
FEED_ARCH=cs08q1armel

TMP=/data/tmp/optware-$$

### END of VARIABLES

### FUNCTIONS

# Name:        log
# Arguments:   Message
# Description: logs Message to $LOG
log() {
	echo "$@" >> $LOG
}


# Name:        yesno
# Arguments:   Question
# Description: Asks a yes/no Question, returns 1 for yes, 0 for no
yesno() {
	IN=""
	until [ -n "$IN" ] ; do
		read -p "${@} " IN
		case "$IN" in
			y|Y|yes|YES)	return 1;;
			n|N|no|NO)	return 0;;
			*)		IN="";;
		esac
	done
}


# Name:        error
# Arguments:   Message
# Description: Displays FAILED followed by Message
error() {
	echo "FAILED"
	log "ERROR: ${@}"
	echo "$@"
	echo
	echo "To view ${LOG}, type:"
	echo
	echo "cat ${LOG}"
	echo
	echo
	return 1
}


# Name:        get_version
# Arguments:   Package
# Description: Checks to see if Package is installed, or if there is an upgrade
#              Returns 1 if the package is not installed or an upgrade is available,
#              0 otherwise.
get_version() {
	PKG=$1
	ipkg-opt info $PKG | grep -q "install user installed"
	RETURN="$?"
	if [ "$RETURN" -eq 0 ] ; then
		count=$(ipkg-opt info "$PKG" | grep Status: | wc -l)
	fi
	if [ "$RETURN" -eq 1 ] || [ $count -gt 1 ] ; then
		return 1
	else
		return 0
	fi
}


# Name:        getipkginfo
# Arguments:   none
# Description: Downloads the ipkg-opt Package file, determines the latest version and md5sum of ipkg-opt 
getipkginfo() {
	if [ -f /tmp/Packages ] ; then
		log "Removing existing Package file: "
		echo -n "Removing existing Package file: "
		rm -f /tmp/Packages || error "Failed to remove /tmp/Package" || return 1
		log "OK"
		echo "OK"
	fi
	log "Downloading the ipkg-opt Package file from the Optware package feed: "
	echo -n "Downloading the ipkg-opt Package file from the Optware package feed: "
	cd /tmp || error "Failed to change directory to /tmp" || return 1
	wget $FEED_URL/$FEED_ARCH/cross/unstable/Packages >> "$LOG" 2>&1 || error "Failed to download Packages file" || return 1
	IPKG_FILE=$(awk 'BEGIN { RS = "" }; /^Package: ipkg-opt\n/ {print}' Packages | awk '/^Filename:/ {print $2}')
	IPKG_SUM=$(awk 'BEGIN { RS = "" }; /^Package: ipkg-opt\n/ {print}' Packages | awk '/^MD5Sum:/ {print $2}')
	if [ -z "$IPKG_FILE" ] ; then
		error "Could not determine the file name of the ipkg-opt package" || return 1
	fi
	if [ -z "$IPKG_SUM" ] ; then
		error "Could not determine the proper md5sum of the ipkg-opt package" || return 1
	fi
	echo "${IPKG_SUM}  ${IPKG_FILE}" > "${IPKG_FILE}.md5sum" || error "Failed to create ${IPKG_FILE}.md5sum" || return 1
	log "OK"
	echo "OK"
}


# Name:        getipkg
# Arguments:   none
# Description: Downloads and installs the ipkg-opt package
getipkg() {
	log "Downloading the latest ipkg-opt package from the Optware package feed: "
	echo -n "Downloading the latest ipkg-opt package from the Optware package feed: "
	cd /tmp || error "Failed to change directory to /tmp" || return 1
	wget "$FEED_URL/$FEED_ARCH/cross/unstable/${IPKG_FILE}" >> "$LOG" 2>&1 || error "Failed to download ${IPKG_FILE}" || return 1
	log "OK"
	echo "OK"
	log "Checking the md5sum of "
	echo -n "Checking the md5sum of "
	md5sum -c "${IPKG_FILE}.md5sum" >> "$LOG" 2>&1
	md5sum -c "${IPKG_FILE}.md5sum" || return 1
	log "Installing the ipkg-opt package: "
	echo -n "Installing the ipkg-opt package: "
	mkdir -p /tmp/ipkg-opt || error "Failed to create /tmp/ipkg-opt" || return 1
	cd /tmp/ipkg-opt || error "Failed to cd to /tmp/ipkg-opt" || return 1
	tar xzf ../"$IPKG_FILE" || error "Failed to unpack ${IPKG_FILE}" || return 1
	cd / || error "Failed to change directory to /" || return 1
	tar xzf /tmp/ipkg-opt/data.tar.gz || error "Failed to unpack data.tar.gz" || return 1
	log "OK"
	echo "OK"
	log "Cleaning up temporary files: "
	echo -n "Cleaning up temporary files: "
	rm /tmp/"$IPKG_FILE"
	rm /tmp/"${IPKG_FILE}.md5sum"
	rm -rf /tmp/ipkg
	log "OK"
	echo "OK"
}

# Name:        updateipkg
# Arguments:   none
# Description: Update the Optware package database
updateipkg() {
	log "Updating the Optware package database: "
	echo -n "Updating the Optware package database: "
	ipkg-opt update >> "$LOG" 2>&1 || error "Failed to update the local Optware package database" || return 1
	log "OK"
	echo "OK"
}


# Name:        mkuser
# Arguments:   none
# Description: Interactively create a regular user
mkuser() {
	log "Creating an unprivileged user account to be used when logging in..."
	echo
	echo
	echo "Creating an unprivileged user account to be used when logging in..."
	until [ -n "$MYUSER" ] ; do
		read -p "Enter the username of your unprivileged user: " MYUSER
		if [ -n "$MYUSER" ] ; then
			check=$(echo "$MYUSER" | tr -d '[a-z]')
			if [ "$MYUSER" = "$check" ] ; then
				echo "\"$USERNAME\" is an invalid username"
				echo "Usernames must contain at least 1 letter"
				MYUSER=""
			fi
			if [ -n "$MYUSER" ] ; then
				check=$(echo "$MYUSER" | tr -d '[A-Z][a-z][0-9]-_')
				if [ -n "$check" ] ; then
					echo "\"$USERNAME\" is an invalid username"
					echo "Usernames may only contain letters, numbers, dashes (-) and underscores (_)"
					MYUSER=""
				fi
			fi
			if [ -n "$MYUSER" ] ; then
				check=$(echo "$MYUSER" | wc -c)
				if [ $check -lt 4 ] ; then
					echo "\"$USERNAME\" is an invalid username"
					echo "Usernames must contain at least 3 characters"
					MYUSER=""
				fi
			fi
			if [ -n "$MYUSER" ] ; then
				LOWERUSER=$(echo "$MYUSER" | tr '[A-Z]' '[a-z]')
				if [ "$MYUSER" != "$LOWERUSER" ] ; then
					echo "Usernames should be lowercase.  Using \"${LOWERUSER}\""
					MYUSER="$LOWERUSER"
				fi
			fi
			if [ -n "$MYUSER" ] ; then
				grep -q ^"$MYUSER": /etc/passwd
				if [ "$?" -eq 0 ] ; then
					UUID=$(awk 'BEGIN {FS=":"} {if ($1 == "'"$MYUSER"'") print $3}' /etc/passwd)
					log "${MYUSER} is an existing username (UID: ${UUID})"
					echo "WARNING: ${MYUSER} is an existing username (UID: ${UUID})"
					if [ "$UUID" -lt 1000 ] ; then
						MYUSER=""
					else
						yesno "Would you like to create another account?"
						case "$?" in
							0)	log "Using ${MYUSER}.  No new user"
								NONEWUSER=yes
								echo
								echo
								return 0
								break;;
							1)	log "Not using ${MYUSER}"
								MYUSER="";;
						esac
					fi
				fi
			fi
			if [ -n "$MYUSER" ] ; then
				adduser -h /opt/home/$MYUSER -s /opt/bin/bash $MYUSER || MYUSER=""
			fi
		fi
	done
}

# Name:        doprofile
# Arguments:   Username
# Description: Make a reasonable /etc/profile
doprofile()  {
cat > /opt/etc/profile << EOF
export PS1='[\u@\h \W]\\$ '
export PATH='/system/xbin:/opt/sbin:/opt/bin:/sbin:/sbin:/system/sbin:/system/bin'
export LD_LIBRARY_PATH='/opt/lib:/system/lib'
EOF
}



# Name:        dosudo
# Arguments:   Username
# Description: Grants sudo privs for Username
dosudo() {
	log "Enabling root privileges for ${MYUSER}: "
	echo -n "Enabling root privileges for ${MYUSER}: "
	chmod 640 /opt/etc/sudoers || error "Failed to set the permissions on /opt/etc/sudoers" || return 1
	echo "$MYUSER ALL=(ALL) ALL" >> /opt/etc/sudoers || error "Failed to update /opt/etc/sudoers" || return 1
	echo "$MYUSER ALL=NOPASSWD: /opt/libexec/sftp-server" >> /opt/etc/sudoers || error "Failed to update /opt/etc/sudoers" || return 1
	chmod 440 /opt/etc/sudoers || error "Failed to set the permissions on /opt/etc/sudoers" || return 1
	log "OK"
	echo "OK"
}


# Name:        installpkg
# Arguments:   Package1 [Package2] [Package3] [...]
# Description: Installs Package
installpkg() {
	for pkg in "$@" ; do
		log "Installing ${pkg}: "
		echo -n "Installing ${pkg}: "
		ipkg-opt install "$pkg" >> "$LOG" 2>&1 || error "Failed to install ${pkg}" || return 1
		log "OK"
		echo "OK"
	done
}

# Name:        smart_install
# Arguments:   Package1 [Package2] [Package3] [...]
# Description: Installs Package


smart_install() {
	for pkg in "$@" ; do
		get_version $pkg
		if [ "$?" -eq 1 ] ; then
			installpkg $pkg || exit 1
		else
			log "$pkg is already installed and no upgrades are available"
			echo "$pkg is already installed and no upgrades are available"
		fi
	done
}


# Name:        patchramdisk
# Arguments:   none
# Description: patches nook color ramdisk to enable rc.local
patchramdisk() {
	RDFILE=uRamdisk
	cd $TMP

	mkdir rd mnt
	mknod mmcblk0 b 179 0; mknod mmcblk0p1 b 179 1
	mount mmcblk0p1 mnt
	
	if [ -e $TMP/mnt/$RDFILE ]
	then
		echo "ramdisk $TMP/mnt/${RDFILE} found" >> $LOG

		cd $TMP/rd
		dd if=$TMP/mnt/$RDFILE bs=64 skip=1| gunzip -c |cpio -i
		if grep 'service optware-init' init.rc
		then
			echo "Ramdisk was already patched, skipping."
			log "Ramdisk was already patched, skipping."
		else
			echo -n "Patching Ramdisk: "
			log "Patching Ramdisk: "
			mount -o remount,rw /mnt
			if [ ! -e $TMP/mnt/$RDFILE.pre-optware ]; then
				cp $TMP/mnt/$RDFILE $TMP/mnt/$RDFILE.pre-optware
			fi
			cp init.rc $TMP/init.rc.bak
			cat >> init.rc << EOF

service optware-init /system/bin/sh /data/opt/etc/optware-init.sh
	user root
	oneshot
EOF
			find . -regex "./.*"| cpio -o -H newc | gzip > $TMP/ramdisk.gz
			cd $TMP
			mkimage -T ramdisk -C gzip -A arm \
				-d $TMP/ramdisk.gz $TMP/mnt/$RDFILE
			echo "OK"
			log "OK"
		fi
		umount $TMP/mnt
	else
		echo "Could not get at the ramdisk"
		log "Could not get at the ramdisk"
	fi
}


### END FUNCTIONS

# Bootstrap the bootstrap
umask 022
mkdir /data/tmp
log "Extracting stage2: "
echo "Extracting stage2: "

# Only make directory if does not exist
/system/bin/ls $TMP > /dev/null 2>&1 || mkdir $TMP
miniunz -oe $0 -d $TMP
cd $TMP
chmod 755 busybox
# support unix style mount commands
./busybox [ ! -e /system/etc/mtab ] && ./busybox ln -s /proc/mounts /system/etc/mtab

# Mount the root fs rw
log "Mounting the root file system read-write: "
echo -n "Mounting the root file system read-write: "
mount -o remount,rw rootfs /  >> "$LOG" 2>&1 || error "Failed to mount / read/write" || exit 1
log "OK"
echo "OK"

echo -n "Remounting:  "
log "Remounting:"
for FS in / /system /data; do
    echo -n " $FS"
	log "Remounting $FS"
	./busybox mount -o remount,rw,suid,dev $FS
done; echo

if ./busybox [ -x /system/xbin/busybox ] && ./busybox [ -x /system/xbin/yes ] ; then
	echo "Static busybox already installed."
	log "Static busybox already installed."
else
	echo "Installing static busybox"
	log "Installing static busybox"
	mkdir /system/xbin
	./busybox cp -p busybox /system/xbin

	busybox --install -s /system/xbin 
	# rehash, busybox commands should exist preferentially in our path now
	hash -r
fi

echo "Extracting supplemental files"
log "Extracting supplemental files"
tar xzf stage2.tar.gz
cd stage2

if [ ! -d /data/opt ]; then
  cp -r opt /data
fi


# HACK: temp symlinks, these should go in rc.local
for LNDIR in /data/opt /data/opt/var /data/opt/home /system/bin /system/lib; do
	TARGET=`echo $LNDIR|sed 's/.*\//\//'`
	if [ ! -e $TARGET ]; then
		echo "Linking $TARGET -> $LNDIR"
		ln -s $LNDIR $TARGET
	else
		echo "Note: $TARGET already present"
	fi
done;  hash -r	

# HACK: google DNS
[ ! -e /data/opt/etc/resolv.conf ] && echo 'nameserver 8.8.8.8' > /data/opt/etc/resolv.conf

# some attempt at actual users
[ ! -e /data/opt/etc/passwd ] && echo 'root:x:0:0:root:/opt/home/root:/opt/bin/bash' > /data/opt/etc/passwd
[ ! -e /data/opt/etc/group ]  && echo 'root:x:0:'  > /data/opt/etc/group
[ ! -e /data/opt/etc/shells ] && echo -e '/system/bin/sh\n/bin/sh\n/data/opt/bin/bash\n/opt/bin/bash' > /data/opt/etc/shells

# make a reasonable /etc/profile

# Perm symlinks
for FILE in nsswitch.conf resolv.conf passwd group shells profile; do
	if [ ! -e /etc/$FILE ]; then 
		echo "Linking /opt/etc/$FILE -> /etc/$FILE"
		ln -s /opt/etc/$FILE /etc/$FILE
	else
		echo "Note: /etc/$FILE already present"
	fi
done

# all dynamic executables really expect to see ld-linux.so.3 in /lib
[ ! -e /lib/ld-linux.so.3 ] && ln -s /opt/lib/ld-linux.so.3 /lib/ld-linux.so.3


# Download the Package file and check version
# If there is an upgrade, or if the package is not installed, install it.
getipkginfo || exit 1
if [ -x /opt/bin/ipkg-opt ] ; then
	ipkg_version=$(ipkg-opt --version 2>&1 | awk '{print $3}')
	ipkg_version_maj=$(echo "$ipkg_version" | awk 'BEGIN {FS="[.-]"} {print $1}')
	ipkg_version_min=$(echo "$ipkg_version" | awk 'BEGIN {FS="[.-]"} {print $2}')
	ipkg_version_rev=$(echo "$ipkg_version" | awk 'BEGIN {FS="[.-]"} {print $3}')
	ipkg_version_maj=${ipkg_version_maj:-0}
	ipkg_version_min=${ipkg_version_min:-0}
	ipkg_version_rev=${ipkg_version_rev:-0}
	IPKG_VERSION=$(awk 'BEGIN { RS = "" }; /^Package: ipkg-opt\n/ {print}' /tmp/Packages | awk '/^Version:/ {print $2}')
	IPKG_VERSION_MAJ=$(echo "$IPKG_VERSION" | awk 'BEGIN {FS="[.-]"} {print $1}')
	IPKG_VERSION_MIN=$(echo "$IPKG_VERSION" | awk 'BEGIN {FS="[.-]"} {print $2}')
	IPKG_VERSION_REV=$(echo "$IPKG_VERSION" | awk 'BEGIN {FS="[.-]"} {print $3}')
	
	if [ "$IPKG_VERSION_MAJ" -gt "$ipkg_version_maj" ] ; then
		INSTALL=yes
	elif [ "$IPKG_VERSION_MAJ" -eq "$ipkg_version_maj" ] ; then
		if [ "$IPKG_VERSION_MIN" -gt "$ipkg_version_min" ] ; then
			INSTALL=yes
		elif [ "$IPKG_VERSION_MIN" -eq "$ipkg_version_min" ] ; then
			if [ "$IPKG_VERSION_REV" -gt "$ipkg_version_rev" ] ; then
				INSTALL=yes
			fi
		fi
	fi
else
	INSTALL=yes
fi

if [ "$INSTALL" = "yes" ] ; then
	getipkg
else
	log "The ipkg-opt package is already installed, and there are no upgrades available"
	echo "The ipkg-opt package is already installed, and there are no upgrades available"
fi

# Configure the Optware feeds
if [ ! -f /opt/etc/ipkg/optware.conf ] ; then
	mkdir -p /opt/etc/ipkg || error "Failed to create /opt/etc/ipkg" || exit 1
fi
touch /opt/etc/ipkg/optware.conf || error "Failed to modify /opt/etc/ipkg" || exit 1
NOTIFIED=no
grep -q "^src/gz cross $FEED_URL/$FEED_ARCH/cross/unstable$" /opt/etc/ipkg/optware.conf
if [ "$?" -ne 0 ] ; then
	log "Configuring the Optware feeds: "
	echo -n "Configuring the Optware feeds: "
	NOTIFIED=yes
	echo "src/gz cross $FEED_URL/$FEED_ARCH/cross/unstable" >> /opt/etc/ipkg/optware.conf \
		|| error "Failed to update  /opt/etc/ipkg/optware.conf" || exit 1
fi
grep -q "^src/gz native $FEED_URL/$FEED_ARCH/native/unstable$" /opt/etc/ipkg/optware.conf
if [ "$?" -ne 0 ] ; then
if [ "$NOTIFIED" = "no" ] ; then
	log "Configuring the Optware feeds: "
	echo -n "Configuring the Optware feeds: "
fi
NOTIFIED=yes
echo "src/gz native $FEED_URL/$FEED_ARCH/native/unstable" >> /opt/etc/ipkg/optware.conf \
	|| error "Failed to update  /opt/etc/ipkg/optware.conf" || exit 1
fi

if [ "$NOTIFIED" = "yes" ] ; then
	log "OK"
	echo "OK"
else
	log "/opt/etc/ipkg/optware.conf is already up to date"
	echo "/opt/etc/ipkg/optware.conf is already up to date"
fi

# Update the Optware package database (we can do this no matter what)
updateipkg || exit 1

# Create an unprivledged user (we can do this no matter what, as we'll accept
# an existing user, as long as the UID is greater than 1000
mkuser || exit 1

# Check that sudo is installed, and if not, or if there is an upgrade available, install it

smart_install sudo

# Check that root privileges are enabled for our user, and if not, make it so
if [ ! -f /opt/etc/sudoers ] ; then
	mkdir -p /opt/etc || error "Failed to create /opt/etc" || exit 1
fi
touch /opt/etc/sudoers || error "Failed to modify /opt/etc/sudoers" || exit 1

check=$(awk '{ if ($1 == "'"$MYUSER"'" && $2 == "ALL=(ALL)" && $NF == "ALL") print $0}' /opt/etc/sudoers)
if [ -z "$check" ] ; then
	dosudo || exit 1
else
	log "/opt/etc/sudoers is already up to date"
	echo "/opt/etc/sudoers is already up to date"
fi

# Install supplementary packages
smart_install busybox bash sed cpio less openssh openssh-sftp-server
doprofile

echo
echo "Beginning rebuild of ramdisk to add optware-init service to /init.rc to persist all this."
patchramdisk
echo
log "Setup complete"
echo "Setup complete"
exit 0
