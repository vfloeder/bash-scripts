#!/bin/bash
#
# (c) Bremerhaven 2008 - 2016 Volker Floeder
# 									You may do whatever you like with this script
#
# mount/unmount an image containing several partitions
# syntax is
#		mnt-all.sh image dir
#		mnt-all.sh -d image dir
#		mnt-all.sh -d image 
#		mnt-all.sh -d dir
#
# Beware that we generate a special file in the users homedir to enable
# unmounting with only imagefile/mountpoint. The file looks like
#	~/.mnt-all:${mntdir}:${image}
#
# THIS SCRIPT RELIES ON 'kpartx'
#
# THE SINGLE ARGUMENT UNMOUNT DOES NOT WORK IF EITHER PATH CONTAINS
# ONE OR MORE BACKSLASHES.
# ----------------------------------------------------------------------
# you may create a file like this
#
#	dd if=/dev/zero of=./testfile.dd bs=1024 count=2621440
#	fdisk ./testfile.dd
#		... primary, extended with three fs inside...
#	mnt-all.sh testfile.dd mnt
#	mkfs -t vfat /dev/mapper/p1
#	mkfs -t ext3 /dev/mapper/loop1p5
#	mkfs -t ext3 /dev/mapper/loop1p6
#	mkfs -t ext3 /dev/mapper/loop1p7
#
# then
#	mnt-all.sh testfile.dd mnt
# gives you mnt/p1, mnt/p5, mnt/p6, mnt/p7
#

# ----------------------------------------------------------------------
# Eventually switch to "superuser", avoiding to force the user to type
# 	sudo bash ./mnt-all.sh ....

USER=`whoami`

if [ "$USER" != "root" ]; then
	sudo -u root bash $0 $@
	exit 
fi

argnum=$#

# ----------------------------------------------------------------------

umnt="0"																				# default: mount an image

while getopts ":d" _option
do
	case ${_option} in
	d ) umnt="1" ; shift; let argnum-=1 ;;				# unmount
	esac
done

# ----------------------------------------------------------------------

if [ "$umnt" == "0" ]; then											# mount it
	
	if (( "$argnum" != "2" )); then
		echo mount all partitions of a disk-image, usage: $0 image mount-point
		exit 1
	fi

	image=$1
	mntdir=$2

	if [[ ! -f "${image}" ]]; then
		echo "image \"${image}\" does not exist"
		exit 1
	fi

	if [ -d "${mntdir}" ]; then										# check if mountpoint exists
		files=$(ls -A ${mntdir})										# check if it is empty
		if [ "$files" != "" ]; then
			echo "mount dir not empty"
			exit 1
		fi
	else
		echo "${mntdir} does not exist"
		exit 1
	fi

	kpartx -a ${image}	2>/dev/null >/dev/null		# map all partitions
	
	if [ "$?" != 0 ]; then
		echo "could not map all partitions, broken image?"
	fi
	
	mapped=$(kpartx -l ${image} 2> /dev/null | awk '{print $1}' ) 

	num="0"
	mntnum="0"
	
	for i in ${mapped}														# iterate over all mapped
	do																						# beware that we might have 
		mapdev="/dev/mapper/$i"											# entries for extended partitions
		num="${mapdev: -1}"													# get same number than in p-table
		subdir="p${num}"														# for the mountpoint
		if [ -e "$mapdev" ]; then
			mkdir ${mntdir}/$subdir										# create sub-point
			mount $mapdev ${mntdir}/$subdir 2>/dev/null
			if [[ "$?" != 0 ]]; then									# this might be an extended partition
				rmdir ${mntdir}/$subdir									# we will mount fs from within...
			fi
			let mntnum+=1
		fi
	done
		
	if [ "$mntnum" != "0" ]; then
		cmntdir=${mntdir////\\}											# replace path-separator
		cimage=${image////\\}												#		likewise
		touch ~/.mnt-all:${cmntdir}:${cimage}				# remember image mapping for unmounting
	else
		echo "could not mount any partiton"
		exit 1
	fi

else																						# unmount all

	if (( "$argnum" == "2" )); then								# we have all we need...
		image=$1
		mntdir=$2
	elif (( "$argnum" == "1" )); then							# just one argument supplied
		if [ -d "$1" ]; then												# mount-point?
			mntdir=$1
			image="*"
		elif [ -f "$1" ]; then											# image given
			mntdir="*"
			image=$1
		else
			echo "$1 is either mount-point nor image-file"
			exit 1
		fi
	
		cmntdir=${mntdir////\\\\}										# replace path-separator		
		cimage=${image////\\\\}											#		likewise
	
		pattern=".mnt-all\:${cmntdir}\:${cimage}"

		echo pattern=$pattern

		patnum=0
		cfghint=""

		for f in `ls ~/$pattern` ###`find ~ -type f -name $pattern`
		do
			echo found $f
			if [ -f "$f" ]; then
				let patnum+=1
				cfghint=$f
			fi
		done		
			
		if [ "$patnum" != "1" ]; then								# must be unique
			echo "invalid hint-file"
			exit 1
		fi
		
		# we have a valid file, so get the infos we need
		aifs=$IFS
		IFS=":"
		idx=0
		for f in $cfghint
		do
			arr[$idx]=$f
			let idx+=1
		done
		IFS=$aifs
		
		if [ "$image" == "*" ]; then								# fill image name
			cimage="${arr[2]}"
			image=${cimage//\\//}
		else																				# fill mount point
			cmntdir="${arr[1]}"
			mntdir=${cmntdir//\\//}
		fi
		
	else
		echo "unmount all partitions of a disk-image, usage: $0 -d image mount-point"
		exit 1
	fi

	files=""																			# get all sub-points 
																								# assume noone messed with them
	if [ -d "${mntdir}" ]; then										# check mountpoint
		files=$(ls -A ${mntdir})										#
		if [ "$files" == "" ]; then									# nothing here?
			echo "mount dir is empty"
			exit 1
		fi
	else
		echo "${mntdir} does not exist"
	fi
	
	num="0"
	for i in ${files}															# unmount all partitions
	do
		subdir="${i}"
		umount ${mntdir}/$subdir										# unmount partition
		rmdir ${mntdir}/$subdir											# remove sub-point
	done

	kpartx -d ${image} >/dev/null	2>/dev/null			# remove mapping
	
	rm -f ~/.mnt-all:${mntdir}:${image} >/dev/null	2>/dev/null
fi
