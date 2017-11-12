zfs destroy -r root/jail/base
zfs destroy -r root/jail/skel

zfs create root/jail/base
zfs create root/jail/skel

#cd /usr/src
#make installworld DESTDIR=/jail/base

echo "Extracting base"
tar -C /jail/base -xf base.txz

echo "splitting skel from base"
mkdir /jail/skel/home
mv /jail/base/etc /jail/skel
mv /jail/base/usr/local /jail/skel/usr-local
mv /jail/base/tmp /jail/skel
chflags noschg /jail/base/var/empty
mv /jail/base/var /jail/skel
chflags schg /jail/skel/var/empty
mv /jail/base/root /jail/skel

#mergemaster -t /jail/skel/var/tmp/temproot -D /jail/skel -i
#cd /jail/skel
#rm -R bin boot lib libexec mnt proc rescue sbin sys usr dev

echo "setting up symlinks"

cd /jail/base
mkdir .rw
ln -s .rw/etc etc
ln -s .rw/home home
ln -s .rw/media media
ln -s .rw/root root
ln -s .rw/tmp tmp
ln -s .rw/var var
cd usr
ln -s ../.rw/usr-local local

echo "done!"
