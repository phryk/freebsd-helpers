set -E

devices=$@
if [ "$devices" = "" ]
then
    echo "No devices to format passed."
    exit 1
fi

echo "This will make absolutely destructive changes to these devices: $devices"
echo "Type in 'yes' to continue."
read optin

if [ "$optin" = "yes" ] # yay for sh! miss a few spaces and kill your system, why not?
then

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
        gpart add -s 94 -t freebsd-boot -l gptzfsboot-$i $device
        gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $device
        echo ""


        echo "Adding boot partition."
        gpart add -s 2G -t freebsd-zfs -l boot-$i $device
        echo ""


        echo "Adding swap partition."
        gpart add -s 2G -t freebsd-swap -l swap-$i $device
        echo ""


        echo "Adding var partition."
        gpart add -s 20G -t freebsd-ufs -l var-$i $device
        echo ""


        echo "Adding poudriere partition."
        gpart add -s 20G -t freebsd-zfs -l poudriere-$i $device
        echo ""


        echo "Adding down partition."
        gpart add -s 100G -t freebsd-ufs -l down-$i $device
        echo ""


        echo "Adding root partition using rest of space."
        gpart add -t freebsd-zfs -l root-$i $device
        echo ""


        echo "Creating boot zpool"

        if [ ! -d "/tmp/boot" ]
        then
            mkdir /tmp/boot
        fi
        zpool create -fm /zboot -o altroot=/tmp/boot boot gpt/boot-$i
        
        mkdir /tmp/boot/zboot/boot
        echo ""

        echo "Generating secret key."
        key_path="/tmp/boot/zboot/boot/disk.key"
        dd if=/dev/random of=$key_path bs=4096 count=1
        echo ""

        echo "Creating geli containers for all partitions to be crypted."
        tocrypt="gpt/var-$i gpt/poudriere-$i gpt/down-$i gpt/root-$i"
        for partition in $tocrypt
        do
            geli init -b -e AES-XTS -l 256 -K $key_path -s 4096 $partition
        done
        echo ""

        echo "Attaching geli containers."
        for partition in $tocrypt
        do
            geli attach -k $key_path $partition
        done
        echo ""


    done
else
    echo "That wasn't 'yes': '$optin'"
fi
