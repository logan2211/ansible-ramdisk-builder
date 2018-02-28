#!/bin/sh
# Copyright 2016, Logan Vig <logan2211@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

case $1 in
  prereqs)
    exit 0
    ;;
esac

include() {
	[ -f "$1" ] && . "$1"
}

#initramfs-tools functions
include /scripts/functions

create_tmpfs_ephemeral() {
  OVERLAY_SIZE=2500M
  for x in $(cat /proc/cmdline); do
    case $x in
    OVERLAY_SIZE=*)
      OVERLAY_SIZE="${x#OVERLAY_SIZE=}"
    ;;
    esac
  done

  mount -t tmpfs -o size="${OVERLAY_SIZE}" tmpfs /live/ephemeral
}

create_zram_ephemeral() {
  OVERLAY_SIZE=5G
  OVERLAY_MKFS='mkfs.ext4'
  OVERLAY_COMP='lzo'
  OVERLAY_COMP_STREAMS='8'
  for x in $(cat /proc/cmdline); do
    case $x in
    OVERLAY_SIZE=*)
      OVERLAY_SIZE="${x#OVERLAY_SIZE=}"
    ;;
    OVERLAY_MKFS=*)
      OVERLAY_MKFS="${x#OVERLAY_MKFS=}"
    ;;
    OVERLAY_COMP=*)
      OVERLAY_COMP="${x#OVERLAY_COMP=}"
    ;;
    OVERLAY_COMP_STREAMS=*)
      OVERLAY_COMP_STREAMS="${x#OVERLAY_COMP_STREAMS=}"
    ;;
    esac
  done

  modprobe zram
  zramctl -a "${OVERLAY_COMP}" -s "${OVERLAY_SIZE}" -t "${OVERLAY_COMP_STREAMS}" /dev/zram0
  $OVERLAY_MKFS /dev/zram0
  mount /dev/zram0 /live/ephemeral
}

mountroot () {
  exec 6>&1
  exec 7>&2
  exec > boot.log
  exec 2>&1
  tail -f boot.log >&7 &
  tailpid="${!}"

  if [ -n "$debug" ]; then
    LIVE_DEBUG=1
    set -x
  fi

  # ephemeral backing store type used for read-write layer of overlay
  # supported options: tmpfs, zram
  OVERLAY_BACKING_STORE="tmpfs"
  for x in $(cat /proc/cmdline); do
    case $x in
    OVERLAY_BACKING_STORE=*)
      OVERLAY_BACKING_STORE="${x#OVERLAY_BACKING_STORE=}"
    ;;
    esac
  done

  # Once the system is booted, the base image will be pivoted and overlay
  # mounted as so (example uses zram backing store):
  # $ mount | grep /live
  # ram on /live/medium type ramfs (rw,relatime) <- squashfs stored here
  # /dev/loop0 on /live/base type squashfs (ro,relatime) <- squashfs mounted here
  # /dev/zram0 on /live/ephemeral type ext4 (rw,relatime,data=ordered) <- overlay rw ramdisk layer
  # overlay on / type overlayfs (rw,noatime,lowerdir=/live/base,upperdir=/live/ephemeral/rw,workdir=/live/ephemeral/work)
  # Tree of /live:
  # /live
  # |-- base
  # |   |-- bin
  # |   |-- boot
  # |   |-- dev
  # |   |-- etc
  # |   |-- home
  # |   |-- lib
  # |   |-- lib64
  # |   |-- media
  # |   |-- mnt
  # |   |-- opt
  # |   |-- proc
  # |   |-- root
  # |   |-- run
  # |   |-- sbin
  # |   |-- srv
  # |   |-- sys
  # |   |-- tmp
  # |   |-- usr
  # |   `-- var
  # |-- ephemeral
  # |   |-- rw
  # |   |   `-- var
  # |   `-- work
  # |       `-- work
  # `-- medium
  #     `-- live.squashfs

  # Prepare the read-only layer (squashfs)
  mkdir -p /live/base /live/ephemeral
  mount /live/medium/live.squashfs /live/base

  # Prepare the read-write layer (tmpfs, zram, etc)
  case $OVERLAY_BACKING_STORE in
    zram)
      create_zram_ephemeral
    ;;
    tmpfs)
      create_tmpfs_ephemeral
    ;;
  esac

  # Prepare and mount the overlay
  mkdir /live/ephemeral/work /live/ephemeral/rw
  mount -t overlayfs -o noatime,lowerdir=/live/base,upperdir=/live/ephemeral/rw,workdir=/live/ephemeral/work overlay ${rootmnt}
  for i in medium base ephemeral; do
    mkdir -p "${rootmnt}/live/${i}"
    mount -o move "/live/${i}" "${rootmnt}/live/${i}"
  done

  if [ -n "$LIVE_DEBUG" ]; then
    set +x
  fi

  exec 1>&6 6>&-
  exec 2>&7 7>&-
  kill ${tailpid}
  [ -w "${rootmnt}/var/log/" ] && mkdir -p "${rootmnt}/var/log/live" && cp boot.log "${rootmnt}/var/log/live" 2>/dev/null
}
