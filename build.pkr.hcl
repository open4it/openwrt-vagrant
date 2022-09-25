variable "build_dir" {
  type    = string
  default = "build"
}

variable "output_dir" {
  type    = string
  default = "output"
}

variable "vm_name" {
  type    = string
  default = "openwrt"
}

locals {
  boot_command = [
    "<enter><wait>",
    "passwd <<EOF<enter>vagrant<enter>vagrant<enter>EOF<enter>",
    "uci set network.@device[0].ports=''<enter>",
    "uci set network.mng='interface'<enter>",
    "uci set network.mng.ifname='eth0'<enter>",
    "uci set network.mng.proto='dhcp'<enter>",
    "uci commit<enter>",
    "reload_config<enter>",
    "fsync /etc/config/network<enter>",
    "/etc/init.d/network restart<enter>",
    "/etc/init.d/firewall restart<enter>"
  ]
}

source "qemu" "openwrt-libvirt" {
  boot_command     = local.boot_command
  boot_wait        = "20s"
  cpus             = 1
  disk_image       = true
  disk_interface   = "virtio"
  format           = "qcow2"
  headless         = true
  iso_checksum     = "none"
  iso_url          = "file://${var.build_dir}/${var.vm_name}.img"
  memory           = 128
  net_device       = "virtio-net"
  shutdown_command = "poweroff"
  ssh_password     = "vagrant"
  ssh_username     = "root"
  ssh_wait_timeout = "300s"
  vm_name          = "${var.vm_name}"
}

source "virtualbox-ovf" "openwrt-virtualbox" {
  boot_command         = local.boot_command
  boot_wait            = "20s"
  guest_additions_mode = "disable"
  headless             = true
  shutdown_command     = "poweroff"
  source_path          = "${var.build_dir}/${var.vm_name}.ovf"
  ssh_password         = "vagrant"
  ssh_username         = "root"
  ssh_wait_timeout     = "120s"
  vboxmanage = [
    ["modifyvm", "{{ .Name }}", "--audio", "none"],
    ["modifyvm", "{{ .Name }}", "--boot1", "disk"],
    ["modifyvm", "{{ .Name }}", "--cpus", 1, "--memory", 128, "--vram", 16],
    ["modifyvm", "{{ .Name }}", "--nic1", "nat"],
    ["modifyvm", "{{ .Name }}", "--nic2", "nat"],
    ["modifyvm", "{{ .Name }}", "--nic3", "hostonly", "--hostonlyadapter3", "vboxnet0"],
    ["modifyvm", "{{ .Name }}", "--usb", "off"],
    ["modifyvm", "{{ .Name }}", "--usbxhci", "off"]
  ]
  vboxmanage_post = [
    ["modifyvm", "{{ .Name }}", "--nic1", "null"],
    ["modifyvm", "{{ .Name }}", "--nic2", "nat"],
    ["modifyvm", "{{ .Name }}", "--nic3", "hostonly", "--hostonlyadapter3", "vboxnet0"],
  ]
  vm_name = "${var.vm_name}"
}

build {
  sources = [
    "source.qemu.openwrt-libvirt",
    "source.virtualbox-ovf.openwrt-virtualbox"
  ]

  provisioner "shell" {
    expect_disconnect   = "true"
    inline_shebang      = "/bin/ash -eux"
    inline              = [

      "uci set network.@device[0].ports='eth0'",
      "uci set network.mng='interface'",
      "uci set network.mng.ifname='eth2'",
      "uci set network.mng.proto='dhcp'",
      "uci commit",
      "reload_config",
      "fsync /etc/config/network",
      "rm -f /etc/dropbear/dropbear_rsa_host_key",
    ]
    start_retry_timeout = "1m"
  }

  post-processor "vagrant" {
    output               = "${var.output_dir}/${var.vm_name}-${source.type}.box"
  }
}