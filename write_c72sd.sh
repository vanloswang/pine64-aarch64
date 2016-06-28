#!/bin/sh
#
#set -e

SIMPLE_IMGXZ=https://www.stdin.xyz/downloads/people/longsleep/pine64-images/simpleimage-pine64-latest.img.xz
CENTOS_IMGXZ=http://mirror.centos.org/altarch/7/isos/aarch64/CentOS-aarch64.img.xz
CWD=${PWD}
SD="$1"

confirm2continue() {
    echo "Now will write centos images to ${SD}, and it will damage the data on it!!!"
    echo "Please confirm, y/n?"
    while true 
    do
        read choice
        if [ "${choice}" == "y" -o "${choice}" == "Y" ]; then
            break
        elif [ "${choice}" == "n" -o "${choice}" == "N" ]; then
            exit 0
        else    
            echo "Invalid input, please input again."
        fi
    done
}

do_init() {
    if [ -z "${SD}" ]; then
	    echo "Usage: $0 {/dev/sdx}"
        echo "      sdx is specified to your sd!!!"
    	exit 1
    fi

    if [ "$(id -u)" -ne "0" ]; then
	    echo "This script requires root."
    	exit 1
    fi

    SD=$(readlink -f "${SD}")
    if [ ! -b "${SD}" ]; then
	    echo "Destination ${SD} not found or not a block device."
    	exit 1
    fi
    
    confirm2continue 
    confirm2continue
}

dwn_image() {
    IMG_XZ=${1##*"/"}
    if [ ! -f "${IMG_XZ%".xz"*}" ]; then
	    echo "Downloading images ${IMG_XZ}..."
        if [ -f ${IMG_XZ} ]; then
            rm -rf ${IMG_XZ}
        fi
	    wget -O ${1##*"/"} $1
        xz -d ${1##*"/"}
    fi
}

dd_img2sd() {
    DEV_PARTITIONS=`ls ${SD}*`
    for partition in ${DEV_PARTITIONS}
    do
        umount ${partition}
    done

    echo -n "Write simple image ... "
    IMG_XZ=${SIMPLE_IMGXZ##*"/"}
    SIMPLE_IMG=${IMG_XZ%".xz"*}    
    dd if=${SIMPLE_IMG} of=${SD} bs=1M oflag=sync
    /bin/echo -e "d\n2\nn\np\n2\n143360\n16777215\nw\n" | fdisk ${SD}
    mkfs.ext4 -O ^has_journal -b 4096 -L rootfs  ${SD}2

    echo -n "Copy CentOS aarch64 rootfs ... "
    IMG_XZ=${CENTOS_IMGXZ##*"/"}
    CENTOS_IMG=${IMG_XZ%".xz"*}
    TMPDIR=`mktemp -d`
    mount ${SD}2 ${TMPDIR}
    C7ROOTFS_TMPDIR=`mktemp -d`
    mount -o ro,loop,offset=2622488576 ${CWD}/${CENTOS_IMG} ${C7ROOTFS_TMPDIR}
    cp -ar ${C7ROOTFS_TMPDIR}/* ${TMPDIR}
    umount "${C7ROOTFS_TMPDIR}" 
    rm -rf ${C7ROOTFS_TMPDIR}

    echo -n "Copy platform scripts ... "
	# Install platform scripts
	mkdir -p "${TMPDIR}/usr/local/sbin"
    if [ -f ./build-pine64-image/simpleimage/platform-scripts/pine64_update_kernel.sh -o -f ./build-pine64-image/simpleimage/platform-scripts/pine64_update_uboot.sh ]; then
        rm -rf build-pine64-image
        git clone https://github.com/longsleep/build-pine64-image
    fi
	cp -av ./build-pine64-image/simpleimage/platform-scripts/{pine64_update_kernel.sh,pine64_update_uboot.sh} "${TMPDIR}/usr/local/sbin"
	chown root.root "${TMPDIR}/usr/local/sbin/"*
	chmod 755 "${TMPDIR}/usr/local/sbin/"*

    echo -n "Modify /etc/fstab ... "
# Create fstab
cat <<EOF > "${TMPDIR}/etc/fstab"
# <file system>	<dir>	<type>	<options>			<dump>	<pass>
/dev/mmcblk0p1	/boot	vfat	defaults			0		2
/dev/mmcblk0p2	/	ext4	defaults,noatime		0		1
EOF

    umount ${TMPDIR}
    rm -rf ${TMPDIR}
}

#main
do_init
dwn_image ${SIMPLE_IMGXZ}
dwn_image ${CENTOS_IMGXZ}
dd_img2sd
echo "Done - installed system to $SD"
exit 0
