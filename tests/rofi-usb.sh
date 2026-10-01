#!/usr/bin/env bash
# Regression checks for safe USB block-device discovery.

set -o errexit -o nounset -o pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$repository_root/bin/rofi-usb.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

cat >"$fixture/lsblk.json" <<'EOF'
{
  "blockdevices": [
    {
      "path": "/dev/nvme0n1",
      "type": "disk",
      "size": "1T",
      "mountpoints": [],
      "rm": false,
      "tran": "nvme",
      "model": "Internal SSD",
      "children": [
        {
          "path": "/dev/nvme0n1p1",
          "type": "part",
          "size": "1T",
          "mountpoints": ["/"],
          "rm": false,
          "tran": null,
          "model": null
        }
      ]
    },
    {
      "path": "/dev/sdb",
      "type": "disk",
      "size": "64G",
      "mountpoints": [],
      "rm": true,
      "tran": "usb",
      "model": "USB Stick",
      "children": [
        {
          "path": "/dev/sdb1",
          "type": "part",
          "size": "32G",
          "mountpoints": [],
          "rm": false,
          "tran": null,
          "model": null
        },
        {
          "path": "/dev/sdb2",
          "type": "part",
          "size": "32G",
          "mountpoints": ["/media/My Drive"],
          "rm": false,
          "tran": null,
          "model": null
        }
      ]
    },
    {
      "path": "/dev/sdc",
      "type": "disk",
      "size": "8G",
      "mountpoints": [],
      "rm": true,
      "tran": "usb",
      "model": "Super Floppy"
    }
  ]
}
EOF

mountable=$(ROFI_USB_LSBLK_JSON="$fixture/lsblk.json" \
    "$launcher" --list-mountable)
mounted=$(ROFI_USB_LSBLK_JSON="$fixture/lsblk.json" \
    "$launcher" --list-mounted)

[[ $mountable == *$'/dev/sdb1\t32G\t\tUSB Stick'* ]]
[[ $mountable == *$'/dev/sdc\t8G\t\tSuper Floppy'* ]]
[[ $mountable != *nvme* ]]
[[ $mountable != *sdb2* ]]

[[ $mounted == *$'/dev/sdb2\t32G\t/media/My Drive\tUSB Stick'* ]]
[[ $mounted != *nvme* ]]
[[ $mounted != *sdb1* ]]

printf 'rofi-usb tests passed\n'
