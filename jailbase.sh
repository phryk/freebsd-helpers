zfs destroy -r zroot/jail/base
zfs destroy -r zroot/jail/skel

zfs create zroot/jail/base
zfs create zroot/jail/skel

cd /usr/src
make installworld DESTDIR=/jail/base

mkdir /jail/skel/home
mv /jail/base/etc /jail/skel
mv /jail/base/usr/local /jail/skel/usr-local
mv /jail/base/tmp /jail/skel
mv /jail/base/var /jail/skel
mv /jail/base/root /jail/skel

mergemaster -t /jail/skel/var/tmp/temproot -D /jail/skel -i
cd /jail/skel
rm -R bin boot lib libexec mnt proc rescue sbin sys usr dev
