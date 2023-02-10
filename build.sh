#!/bin/bash
set -e

rm -f cloud-init-squash.iso
rm -f build.log
rm -rf working/

reqs=(isolinux syslinux xorriso mmdebstrap squashfs-tools-ng live-boot live-boot-initramfs-tools)
squash_pkgs="cloud-init,openssh-server"

install_req () {
  echo apt-get install $1 -y
  if apt-get -qq install $1; then
    echo "Successfully installed $1" >> build.log
  else
    echo "Error installing $1" >> build.log
  fi
}

# iterate through package names, check if install and if not install if required
for i in "${reqs[@]}"
do
    :
    if dpkg --get-selections | grep -q "$i" >/dev/null; then echo "Package $i already installed" >> build.log; else echo "Installing package requirement $i"; install_req $i >> build.log; fi
done

# setup working env, copy isolinux and newest system kernel/initrd to working
mkdir -p working/{boot,live,isolinux}
cp -rp isolinux/isolinux.cfg working/isolinux/
cp -p /usr/lib/ISOLINUX/isolinux.bin working/isolinux/
cp -p /usr/lib/syslinux/modules/bios/ldlinux.c32 working/isolinux/
cp $(ls -t /boot/vmlinuz* | head -1) working/boot/vmlinuz
cp $(ls -t /boot/initrd* | head -1) working/boot/initrd

# add separators to log file and generate squashfs
echo "Writing mmdebstrap output to build.log"
echo "############################ MMDEBSTRAP LOG BEGIN ############################" >> build.log
mmdebstrap bullseye working/live/filesystem.squashfs --include=`echo $squash_pkgs` --components=main --customize-hook='mkdir -p $1/var/lib/cloud/seed/nocloud' --customize-hook='copy-in cloud-init/* /var/lib/cloud/seed/nocloud/.' >> build.log 2>&1
echo "############################ MMDEBSTRAP LOG END ############################" >> build.log

# notice of iso generation, adding separators to log file and generating iso
echo "Writing xorriso output to build.log"
echo "############################ XORRISO LOG BEGIN ############################" >> build.log
xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -volid "DEBIAN BULLSEYE CLOUD-INIT" -output "cloud-init-squash.iso" -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -eltorito-boot isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table --eltorito-catalog isolinux/isolinux.cat ./working >> build.log 2>&1
echo "############################ XORRISO LOG END ############################" >> build.log

# cleaning/removing working env
rm -rf working/

echo "Output file: ./cloud-init-squash.iso"
