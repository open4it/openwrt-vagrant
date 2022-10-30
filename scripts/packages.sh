#!/bin/ash
# shellcheck shell=dash
set -eux

opkg update
opkg install rsync sudo

# Clean opkg
rm -rf /var/opkg-lists