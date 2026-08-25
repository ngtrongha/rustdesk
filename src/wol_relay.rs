// Subnet WOL broadcast helper used by the deployment agent heartbeat.
use std::collections::HashSet;
use std::net::{IpAddr, Ipv4Addr};

fn ignored_ipv4(ip: Ipv4Addr) -> bool {
    ip.is_loopback() || ip.is_link_local() || ip.is_unspecified()
}

// Returns (subnet_key, interface_addr, broadcast_addr) for usable IPv4 interfaces.
pub fn local_subnets() -> Vec<(String, Ipv4Addr, Ipv4Addr)> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();
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
    out
}

// Primary local IPv4 (first usable interface address), for heartbeat reporting.
pub fn primary_ipv4() -> Option<String> {
    local_subnets().first().map(|(_, addr, _)| addr.to_string())
}

// Broadcasts magic packets to every interface's subnet broadcast plus global
// broadcast. Returns how many MACs were dispatched successfully.
pub fn broadcast_macs(macs: &[String]) -> Result<usize, String> {
    let mut targets: Vec<IpAddr> = vec![IpAddr::V4(Ipv4Addr::BROADCAST)];
    for (_, _, bcast) in local_subnets() {
        targets.push(IpAddr::V4(bcast));
    }
    let mut sent = 0usize;
    let mut last_err = String::new();
    for mac in macs {
        let mac_addr: wol::MacAddr = match mac.trim().parse() {
            Ok(m) => m,
            Err(_) => {
                last_err = format!("invalid MAC: {}", mac);
                continue;
            }
        };
        let mut ok_for_mac = false;
        for target in &targets {
            match wol::send_wol(mac_addr, None, Some(*target)) {
                Ok(_) => ok_for_mac = true,
                Err(e) => last_err = format!("send to {} failed: {}", target, e),
            }
        }
        if ok_for_mac {
            sent += 1;
        }
    }
    if sent == 0 && !last_err.is_empty() {
        return Err(last_err);
    }
    Ok(sent)
}
