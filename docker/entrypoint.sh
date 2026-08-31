#!/bin/sh
set -e

# OpenWrt's br-lan is a self-assigned static address (192.168.1.1 by default) —
# it never runs a DHCP client on its LAN interface, so QEMU's usermode/slirp
# networking (which only knows how to forward to an address IT assigns the
# guest, e.g. 10.0.2.15) has no route to it. A tap device gives the guest a
# real L2 link where its own chosen address is directly reachable as a
# neighbor from this container's network namespace.
ip tuntap add dev tap0 mode tap
ip addr add 192.168.1.2/24 dev tap0
ip link set tap0 up

# Relay the container's own exposed ports (mapped to the host via `docker -p`)
# through to OpenWrt's actual LAN address over the tap link. Logged to files
# rather than left on stdio, since `-serial mon:stdio` below hands stdio to
# the QEMU monitor + guest console — the one place this setup gives us for
# interactive guest-level debugging, and socat's own logs would otherwise
# interleave with it in `docker logs`.
mkdir -p /var/log
start_relay(){
  # port=$1 (host-relay side, matches docker-compose's `ports:`), $2=log file
  while :; do
    socat TCP-LISTEN:"$1",fork,reuseaddr TCP:192.168.1.1:"$1" >>"$2" 2>&1
    echo "$(date -Iseconds) socat relay on port $1 exited (status $?) — restarting in 2s" >>"$2"
    sleep 2
  done
}
start_relay 80 /var/log/socat-80.log &
start_relay 22 /var/log/socat-22.log &

exec qemu-system-x86_64 \
  -enable-kvm -m 256 -smp 1 \
  -drive file=/boot.img,format=raw,if=virtio \
  -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
  -device virtio-net-pci,netdev=net0 \
  -nographic -serial mon:stdio
