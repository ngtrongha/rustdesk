// Subnet WOL broadcast helper used by the deployment agent heartbeat.
use std::collections::HashSet;
use std::net::{Ipv4Addr, SocketAddrV4, UdpSocket};

fn ignored_ipv4(ip: Ipv4Addr) -> bool {
    ip.is_loopback() || ip.is_link_local() || ip.is_unspecified()
}

fn is_virtual_adapter(name: &str, desc: &str, friendly: &str) -> bool {
    let combined = format!("{} {} {}", name, desc, friendly).to_lowercase();
    const VIRTUAL_KEYWORDS: &[&str] = &[
        "virtual", "vbox", "vmware", "hyper-v", "vethernet", "wsl",
        "npcap", "loopback", "tunnel", "tap", "tun", "bluetooth",
        "tailscale", "zerotier", "wireguard", "openvpn", "anyconnect",
        "fortinet", "hamachi", "docker", "container", "parallels", "qemu", "xen",
    ];
    VIRTUAL_KEYWORDS.iter().any(|&k| combined.contains(k))
}

// Returns (subnet_key, interface_addr, broadcast_addr) for usable physical IPv4 interfaces.
pub fn local_subnets() -> Vec<(String, Ipv4Addr, Ipv4Addr)> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();

    // 1. If default interface is present and non-virtual, prioritize it first
    if let Ok(default_iface) = default_net::get_default_interface() {
        let desc = default_iface.description.as_deref().unwrap_or_default();
        let friendly = default_iface.friendly_name.as_deref().unwrap_or_default();
        if !is_virtual_adapter(&default_iface.name, desc, friendly) {
            for ipv4 in &default_iface.ipv4 {
                let addr = ipv4.addr;
                if ignored_ipv4(addr) {
                    continue;
                }
                let o = addr.octets();
                let key = format!("{}.{}.{}", o[0], o[1], o[2]);
                if !seen.contains(&key) {
                    seen.insert(key.clone());
                    let bcast = Ipv4Addr::from(u32::from(addr) | !u32::from(ipv4.netmask));
                    out.push((key, addr, bcast));
                }
            }
        }
    }

    // 2. Scan remaining physical interfaces
    for iface in default_net::get_interfaces() {
        if matches!(
            iface.if_type,
            default_net::interface::InterfaceType::Loopback
                | default_net::interface::InterfaceType::Tunnel
        ) {
            continue;
        }
        let desc = iface.description.as_deref().unwrap_or_default();
        let friendly = iface.friendly_name.as_deref().unwrap_or_default();
        if is_virtual_adapter(&iface.name, desc, friendly) {
            continue;
        }

        for ipv4 in &iface.ipv4 {
            let addr = ipv4.addr;
            if ignored_ipv4(addr) {
                continue;
            }
            let o = addr.octets();
            let key = format!("{}.{}.{}", o[0], o[1], o[2]);
            if seen.contains(&key) {
                continue;
            }
            seen.insert(key.clone());
            let bcast = Ipv4Addr::from(u32::from(addr) | !u32::from(ipv4.netmask));
            out.push((key, addr, bcast));
        }
    }

    // 3. Fallback: if all interfaces were filtered out, allow any non-ignored IPv4
    if out.is_empty() {
        for iface in default_net::get_interfaces() {
            for ipv4 in &iface.ipv4 {
                let addr = ipv4.addr;
                if ignored_ipv4(addr) {
                    continue;
                }
                let o = addr.octets();
                let key = format!("{}.{}.{}", o[0], o[1], o[2]);
                if seen.contains(&key) {
                    continue;
                }
                seen.insert(key.clone());
                let bcast = Ipv4Addr::from(u32::from(addr) | !u32::from(ipv4.netmask));
                out.push((key, addr, bcast));
            }
        }
    }

    out
}

// Primary local IPv4 (first usable physical interface address), for heartbeat reporting.
pub fn primary_ipv4() -> Option<String> {
    local_subnets().first().map(|(_, addr, _)| addr.to_string())
}

fn create_magic_packet(mac: [u8; 6]) -> [u8; 102] {
    let mut packet = [0xFF; 102];
    for i in 0..16 {
        packet[6 + i * 6..6 + (i + 1) * 6].copy_from_slice(&mac);
    }
    packet
}

fn parse_mac(s: &str) -> Option<[u8; 6]> {
    let s = s.trim().replace('-', ":");
    let parts: Vec<&str> = s.split(':').collect();
    if parts.len() != 6 {
        return None;
    }
    let mut mac = [0u8; 6];
    for (i, part) in parts.iter().enumerate() {
        mac[i] = u8::from_str_radix(part, 16).ok()?;
    }
    Some(mac)
}

// Broadcasts magic packets to every physical interface's subnet broadcast plus global broadcast.
// Uses 0.0.0.0:0 with SO_BROADCAST as primary broadcaster to avoid Windows error 10049 (WSAEADDRNOTAVAIL).
pub fn broadcast_macs(macs: &[String]) -> Result<usize, String> {
    let subnets = local_subnets();
    let mut sent = 0usize;
    let mut last_err = String::new();
    let ports = [9u16, 7u16];

    for mac_str in macs {
        let mac = match parse_mac(mac_str) {
            Some(m) => m,
            None => {
                last_err = format!("invalid MAC address: {}", mac_str);
                continue;
            }
        };
        let packet = create_magic_packet(mac);
        let mut packets_sent_for_mac = 0usize;

        // 1. Primary: Global Broadcast from 0.0.0.0:0 (Always permitted on Windows, Linux, macOS)
        if let Ok(socket) = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 0)) {
            let _ = socket.set_broadcast(true);
            for &port in &ports {
                let target_global = SocketAddrV4::new(Ipv4Addr::BROADCAST, port);
                for _ in 0..3 {
                    if let Ok(_) = socket.send_to(&packet, target_global) {
                        packets_sent_for_mac += 1;
                    }
                }
            }

            // Also send to all subnet broadcast candidates from 0.0.0.0 socket
            for (_, iface_ip, bcast_ip) in &subnets {
                let o = iface_ip.octets();
                let candidates = [
                    *bcast_ip,
                    Ipv4Addr::new(o[0], o[1], o[2], 255),     // /24 (e.g. 10.0.2.255)
                    Ipv4Addr::new(o[0], o[1], 255, 255),       // /16 (e.g. 10.0.255.255 - critical for hospital LAN)
                    Ipv4Addr::new(o[0], o[1], o[2] | 3, 255), // /22
                    Ipv4Addr::new(o[0], o[1], o[2] | 1, 255), // /23
                ];
                for &bcast in &candidates {
                    for &port in &ports {
                        let target = SocketAddrV4::new(bcast, port);
                        for _ in 0..2 {
                            if let Ok(_) = socket.send_to(&packet, target) {
                                packets_sent_for_mac += 1;
                            }
                        }
                    }
                }
            }
        }

        // 2. Secondary: Interface-specific broadcast (bound to local interface IP)
        for (_, iface_ip, bcast_ip) in &subnets {
            let bind_addr = SocketAddrV4::new(*iface_ip, 0);
            if let Ok(socket) = UdpSocket::bind(bind_addr) {
                let _ = socket.set_broadcast(true);
                let o = iface_ip.octets();
                let candidates = [
                    *bcast_ip,
                    Ipv4Addr::new(o[0], o[1], o[2], 255),
                    Ipv4Addr::new(o[0], o[1], 255, 255),
                ];
                for &bcast in &candidates {
                    for &port in &ports {
                        let target = SocketAddrV4::new(bcast, port);
                        if let Ok(_) = socket.send_to(&packet, target) {
                            packets_sent_for_mac += 1;
                        }
                    }
                }
            }
        }

        if packets_sent_for_mac > 0 {
            sent += 1;
        } else if last_err.is_empty() {
            last_err = format!("Failed to send magic packet for MAC {}", mac_str);
        }
    }

    if sent == 0 && !last_err.is_empty() {
        return Err(last_err);
    }
    Ok(sent)
}
