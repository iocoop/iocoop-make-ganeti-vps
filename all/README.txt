Version 0.30
=========================================================================

Dear new VPS user,

Here is your new instance.  It was installed with debootstrap (a standard 
debian tool) to install the version of Debian or Ubuntu you requested into
a logical volume (LVM) backed by CEPH (network-raid-1).  In the case of
most VPS host failures, your VPS guest can be booted on another VPS host.

This network RAID-1 is *NOT* a backup.  Please plan accordingly to avoid
the loss of important data because of a larger failure or human error.

Changes because of debootrap:

1) /etc/shadow's root entry has a a null password and an entry in
   /etc/ttyS0 This results in the serial console (from the VPS host)
   can login as root without a password.  To fix set a root password
   with the "passwd" command or remove ttyS0 from /etc/securetty

Changes made to your instance to increase usability and security:

1) /etc/ssh/sshd_config has an added entry "PasswordAuthentication no"
   This prevents any type of bruteforce password attack from succeeding.
2) squid-deb-proxy-client (an ubuntu package) was installed.  This
   searches the local network for a proxy for Ubuntu updates/patches.
   IO Cooperative runs one and the result is saving the coop's network bandwidth
   and much quicker updates/installs for packages.  Since Ubuntu
   packages are signed this is of minimal risk.  To remove run "apt-get
   remove squid-deb-proxy-client"
3) Your key was added to /root/.ssh/authorized_keys
4) Acpid was installed to allow the VPS host to shutdown your server
   cleanly.
5) Changes to /etc/default/grub to allow serial console during boot
   and shutdown.  This allows debugging, recovery, selecting a different
   kernel, etc.

Suggestions for the future:

1) Backup anything important, regularly, and check to make sure they
   work.
2) Patch regularly, Ubuntu LTS releases have 5 years of patches.
3) Set a timezone if you don't like PDT run something like:
    ln -sf /usr/share/zoneinfo/US/Pacific /etc/localtime
4) Running NTP will *NOT* improve time accuracy.  The hardware clock
   of the host is already using NTP to keep accurate.
5) When possible, it's recommended to use certificates over passwords.

