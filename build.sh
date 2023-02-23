#!/bin/bash
set -e

rm -f cloud-init-squash.iso
rm -f build.log
rm -rf working/

reqs=(isolinux syslinux xorriso mmdebstrap squashfs-tools-ng live-boot dosfstools grub-efi mtools linux-image-amd64 proot)
squash_pkgs="cloud-init,sudo"
boot_img_data=working/efitemp
boot_img=working/isolinux/efiboot.img

install_req () {
  echo apt-get install $1 -y
  if apt-get -qq install $1; then
    echo "Successfully installed $1" >> build.log
  else
    echo "Error installing $1" >> build.log
  fi
}

function trap_ctrlc ()
{
    # perform cleanup here
    set +e
    echo "Ctrl-C caught...performing clean up"
    rm -rf working/
 
    # exit shell script with error code 2
    # if omitted, shell script will continue execution
    exit 2
}
 
# initialise trap to call trap_ctrlc function
# when signal 2 (SIGINT) is received
trap "trap_ctrlc" 2

# iterate through package names, check if install and if not install if required
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq apt-utils libterm-readline-gnu-perl dialog >/dev/null 2>&1
for i in "${reqs[@]}"
do
    :
    if dpkg --get-selections | grep -q "$i" >/dev/null; then echo "Package $i already installed" >> build.log; else echo "Installing package requirement $i"; install_req $i >> build.log; fi
done

# setup working env, copy isolinux and newest system kernel/initrd to working
mkdir -p working/{boot,live,isolinux}
mkdir -p working/boot/grub
cp -p boot-config/isolinux.cfg working/isolinux/
cp -p boot-config/grub.cfg working/boot/grub/
cp -p /usr/lib/ISOLINUX/isolinux.bin working/isolinux/
cp -p /usr/lib/syslinux/modules/bios/ldlinux.c32 working/isolinux/
cp $(ls -t /boot/vmlinuz* | head -1) working/boot/vmlinuz
cp $(ls -t /boot/initrd* | head -1) working/boot/initrd

# create efi .img file, use grub to generate efi files
truncate -s 8M $boot_img
mkfs.vfat $boot_img >/dev/null 2>&1
mkdir -p $boot_img_data
mmd -i $boot_img ::/efi
mmd -i $boot_img ::/efi/boot

grub-mkimage \
    -C xz \
    -O x86_64-efi \
    -p /boot/grub \
    -o $boot_img_data/bootx64.efi \
    boot linux search normal configfile \
    part_gpt btrfs ext2 fat iso9660 loopback \
    test keystatus gfxmenu regexp probe \
    efi_gop efi_uga all_video gfxterm font \
    echo read ls cat png jpeg halt reboot

mcopy -i $boot_img $boot_img_data/bootx64.efi ::/efi/boot/bootx64.efi
rm -rf $boot_img_data

# add separators to log file and generate squashfs
echo "Writing mmdebstrap output to build.log"
echo "############################ MMDEBSTRAP LOG BEGIN ############################" >> build.log
mmdebstrap bullseye working/live/filesystem.squashfs --include=`echo $squash_pkgs` --components=main --mode=proot --customize-hook='mkdir -p $1/var/lib/cloud/seed/nocloud' --customize-hook='copy-in cloud-init/* /var/lib/cloud/seed/nocloud/.' --customize-hook='chroot "$1" apt-get install -y openssh-server' --customize-hook='chroot "$1" systemctl enable ssh' >> build.log 2>&1
echo "############################ MMDEBSTRAP LOG END ############################" >> build.log

# notice of iso generation, adding separators to log file and generating iso
echo "Writing xorriso output to build.log"
echo "############################ XORRISO LOG BEGIN ############################" >> build.log
xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -volid "DEBIAN BULLSEYE CLOUD-INIT" -output "cloud-init-squash.iso" -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -eltorito-boot isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table --eltorito-catalog isolinux/isolinux.cat -eltorito-alt-boot -e 'isolinux/efiboot.img' -no-emul-boot -isohybrid-gpt-basdat ./working >> build.log 2>&1
echo "############################ XORRISO LOG END ############################" >> build.log

# cleaning/removing working env
rm -rf working/

echo "Output file: ./cloud-init-squash.iso"
