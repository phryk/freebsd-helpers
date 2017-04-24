set -E

constructionsite="/mnt"
fstab="newfstab"

devices=$@
if [ "$devices" = "" ]
then
    echo "No devices to format passed."
    exit 1
fi

echo "This will make absolutely destructive changes to these devices: $devices"
echo "Make sure that you currently do not have zpools of the names \"root\" and \"boot\"."
echo "Make sure that you currently do not have gmirrors of the names \"var\" and \"down\"."
echo "The new system will be put together at $constructionsite. Make sure it's free."

echo "Type in 'yes' to continue."
read optin

if [ "$optin" = "yes" ] # yay for sh! miss a few spaces and kill your system, why not?
then

    #echo "# device  mountpoint  fstype  options dump    pass" > $fstab

    echo "Filling loader.conf…"
    echo 'geom_eli_load="YES"' >> loader.conf
    echo 'aesni_load="YES"' >> loader.conf
    echo 'zfs_load="YES"' >> loader.conf
    echo 'tmpfs_load="YES"' >> loader.conf
    echo 'coretemp_load="YES"' >> loader.conf
    echo 'beastie_disable="YES"' >> loader.conf
    echo 'kern.vty="vt"' >> loader.conf


    echo ""

    echo "Activating gmirror."
    gmirror load
    echo ""

    echo "Generating secret key."
    key_path="/tmp/disk.key"
    dd if=/dev/random of=$key_path bs=4096 count=1
    echo ""

    i=0 # iterated, used to get different labels per device
    for device in $devices
    do

        i=`expr $i + 1`


        echo "Handling device $device."
        echo ""


        echo "Destroying current partition layout."
        if ! gpart destroy -F $device; then
            echo "Can't (even forcibly) destroy layout of device $device, aborting."
            exit 1
        fi
        echo ""


        echo "Creating new GPT partition layout."
        gpart create -s gpt $device
        echo ""


        echo "Adding gptzfsboot partition."
        gpart add -s 94 -t freebsd-boot -l gptzfsboot-$device $device
        gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $device
        echo ""


        echo "Adding boot partition."
        gpart add -s 2G -t freebsd-zfs -l boot-$device $device
        echo ""


        echo "Adding swap partition."
        gpart add -s 2G -t freebsd-swap -l swap-$device $device
        echo ""


        echo "Adding var partition."
        gpart add -s 20G -t freebsd-ufs -l var-$device $device
        echo ""


        echo "Adding down partition."
        gpart add -s 100G -t freebsd-ufs -l down-$device $device
        echo ""


        echo "Adding root partition using rest of space."
        gpart add -t freebsd-zfs -l root-$device $device
        echo ""



        if [ ! -d "/tmp/boot" ]
        then
            mkdir /tmp/boot
        fi
        
        if [ $i -eq 1 ]
        then
            echo "Creating boot zpool…"
            zpool create -fm /zboot -o altroot=/tmp/boot boot gpt/boot-$device
        else
            echo "Attaching to boot zpool…"
            zpool attach boot gpt/boot-$device
        fi
        
        mkdir /tmp/boot/boot
        echo ""


        echo "Creating geli containers for all partitions to be crypted."
        # root using CBC instead of XTS because zfs already does extensive checksum magics
        geli init -b -e AES-CBC -l 256 -K $key_path -s 4096 gpt/root-$device
        echo "geli_root-${device}_keyfile0_load=\"YES\"" >> loader.conf
        echo "geli_root-${device}_keyfile0_type=\"gpt/root-$device:geli_keyfile0\"" >> loader.conf
        echo "geli_root-${device}_keyfile0_name=\"/boot/disk.key\"" >> loader.conf
        #tocrypt="gpt/var-$device gpt/down-$device gpt/swap-$device"
        tocrypt="var down swap"
        for name in $tocrypt
        do
            geli init -b -e AES-XTS -l 256 -K $key_path -s 4096 gpt/$name-$device
            echo "geli_$name-${device}_keyfile0_load=\"YES\"" >> loader.conf
            echo "geli_$name-${device}_keyfile0_type=\"gpt/$name-$device:geli_keyfile0\"" >> loader.conf
            echo "geli_$name-${device}_keyfile0_name=\"/boot/disk.key\"" >> loader.conf
        done
        echo ""

        echo "/dev/gpt/swap-$device.eli  none    swap    sw  0   0" >> $fstab

        echo "Attaching geli containers."

        geli attach -k $key_path gpt/root-$device
        for name in $tocrypt
        do
            geli attach -k $key_path gpt/$name-$device
        done
        echo ""

        if [ $i -eq 1 ]
        then
            echo "Creating root zpool…"
            zpool create -fm / -o altroot=$constructionsite root gpt/root-$device.eli
            echo 'vfs.root.mountfrom="zfs:root/ROOT/default"' >> loader.conf
            echo ""

            echo "Creating var gmirror…"
            gmirror label -v var /dev/gpt/var-$device.eli
            echo "Creating UFS on var gmirror…"
            newfs -U /dev/mirror/var
            echo "/dev/mirror/var /var ufs rw 0 2" >> $fstab
            echo ""

            echo "Creating down gmirror…"
            gmirror label -v down /dev/gpt/down-$device.eli
            echo "Creating UFS on down gmirror…"
            newfs -U /dev/mirror/down
            echo "/dev/mirror/down /media/down ufs rw 0 2" >> $fstab
            echo ""

        else
            echo "Attaching to boot zpool…"
            zpool attach boot gpt/boot-$device
            echo ""

            echo "Attaching to root zpool…"
            zpool attach root gpt/root-$device.eli
            echo ""

            echo "Adding to var gmirror…"
            gmirror insert var /dev/gpt/var-$device.eli
            echo ""

            echo "Adding to down gmirror…"
            gmirror insert down /dev/gpt/down-$device.eli
            echo ""

        fi

    done


    echo "Exporting boot zpool…"
    zpool export boot
    echo "Re-importing boot zpool at $constructionsite…"
    zpool import -o altroot=$constructionsite boot
    echo ""

    echo "Mounting var…"
    mkdir $constructionsite/var
    mount /dev/mirror/var $constructionsite/var

    echo "Mounting down…"
    mkdir -p $constructionsite/media/down
    mount /dev/mirror/down $constructionsite/media/down
    echo ""

    echo "Preparing boot…"
    mkdir $constructionsite/zboot/boot

    echo ""


    echo "Disk setup done. Press enter to continue."
    read x
    
    echo "Extracting kernel…"
    tar -C $constructionsite -xvf kernel.txz

    echo "Extracting base system…"
    tar -C $constructionsite -xvf base.txz
    
    echo "Moving/symlinking boot…"
    mv $constructionsite/boot $constructionsite/zboot/
    ln -s $constructionsite/zboot/boot $constructionsite/boot
    
    echo "Copying key…"
    cp $key_path $constructionsite/boot/
    
    echo "Creating loader.conf…"
    cat loader.conf >> $constructionsite/boot/loader.conf

    echo "Creating fstab…"
    cat $fstab >> $constructionsite/etc/fstab

    echo "Maybbe it werk now? D:"

else
    echo "That wasn't 'yes': '$optin'"
fi
