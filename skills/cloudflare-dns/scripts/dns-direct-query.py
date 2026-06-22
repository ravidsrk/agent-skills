#!/usr/bin/env python3
"""
Send a DNS query directly to a specific nameserver via UDP.

Used to verify a Cloudflare zone is correct BEFORE flipping NS at
the registrar — public DNS still points to Namecheap, but Cloudflare's
authoritative NS already serve the new zone.

Usage:
    python3 dns-direct-query.py <ns-ip-or-host> <name> [type]

Examples:
    python3 dns-direct-query.py emerson.ns.cloudflare.com example.com A
    python3 dns-direct-query.py 1.1.1.1 api.example.com CNAME
"""
import socket, struct, sys, random, json, re

TYPE_MAP = {
    "A": 1, "NS": 2, "CNAME": 5, "SOA": 6, "PTR": 12,
    "MX": 15, "TXT": 16, "AAAA": 28, "SRV": 33, "CAA": 257,
}
TYPE_REV = {v: k for k, v in TYPE_MAP.items()}


def encode_name(name: str) -> bytes:
    out = b""
    for label in name.rstrip(".").split("."):
        out += bytes([len(label)]) + label.encode()
    return out + b"\x00"


def decode_name(buf: bytes, offset: int) -> tuple[str, int]:
    parts, jumped, original_offset = [], False, offset
    while True:
        length = buf[offset]
        if length == 0:
            offset += 1
            break
        if length & 0xC0 == 0xC0:  # pointer
            ptr = ((length & 0x3F) << 8) | buf[offset + 1]
            if not jumped:
                original_offset = offset + 2
                jumped = True
            offset = ptr
            continue
        offset += 1
        parts.append(buf[offset:offset + length].decode("ascii", errors="replace"))
        offset += length
    return ".".join(parts), (original_offset if jumped else offset)


def parse_rdata(buf: bytes, offset: int, rdlen: int, rtype: int) -> str:
    if rtype == 1:  # A
        return ".".join(str(b) for b in buf[offset:offset + 4])
    if rtype == 28:  # AAAA
        groups = struct.unpack("!8H", buf[offset:offset + 16])
        return ":".join(f"{g:x}" for g in groups)
    if rtype in (2, 5):  # NS, CNAME
        name, _ = decode_name(buf, offset)
        return name
    if rtype == 15:  # MX
        pref = struct.unpack("!H", buf[offset:offset + 2])[0]
        name, _ = decode_name(buf, offset + 2)
        return f"{pref} {name}"
    if rtype == 16:  # TXT
        # may have multiple <length><string> chunks
        end = offset + rdlen
        out = []
        while offset < end:
            slen = buf[offset]
            offset += 1
            out.append(buf[offset:offset + slen].decode("ascii", errors="replace"))
            offset += slen
        return '"' + "".join(out) + '"'
    if rtype == 6:  # SOA
        primary, off = decode_name(buf, offset)
        rname, off = decode_name(buf, off)
        serial, refresh, retry, expire, minimum = struct.unpack("!IIIII", buf[off:off + 20])
        return f"{primary} {rname} {serial}"
    return buf[offset:offset + rdlen].hex()


def resolve_to_ip(host: str) -> str:
    """If host is an IP, return as-is; else query 1.1.1.1 to get its A."""
    if re.match(r"^\d+\.\d+\.\d+\.\d+$", host):
        return host
    # Use socket — sandbox usually has IPv4 connectivity to 1.1.1.1
    try:
        return socket.gethostbyname(host)
    except socket.gaierror:
        # Fall back to DoH at 1.1.1.1
        import urllib.request
        req = urllib.request.Request(
            f"https://1.1.1.1/dns-query?name={host}&type=A",
            headers={"accept": "application/dns-json"},
        )
        data = json.loads(urllib.request.urlopen(req, timeout=5).read())
        for a in data.get("Answer", []):
            if a.get("type") == 1:
                return a["data"]
        raise RuntimeError(f"could not resolve {host}")


def query(ns_host: str, name: str, qtype: str = "A", timeout: float = 5.0):
    qtype_n = TYPE_MAP[qtype.upper()]
    ns_ip = resolve_to_ip(ns_host)

    # Build query
    txid = random.randint(0, 0xFFFF)
    flags = 0x0100  # standard query, RD=1
    header = struct.pack("!HHHHHH", txid, flags, 1, 0, 0, 0)
    question = encode_name(name) + struct.pack("!HH", qtype_n, 1)
    pkt = header + question

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    sock.sendto(pkt, (ns_ip, 53))
    try:
        resp, _ = sock.recvfrom(4096)
    except socket.timeout:
        return {
            "ns": ns_host,
            "ns_ip": ns_ip,
            "name": name,
            "type": qtype,
            "error": "timeout",
            "answers": [],
        }
    finally:
        sock.close()

    # Parse
    if len(resp) < 12:
        return {"error": "short response", "answers": []}
    _, rflags, qd, an, ns_count, ar = struct.unpack("!HHHHHH", resp[:12])
    rcode = rflags & 0x0F

    offset = 12
    # skip questions
    for _ in range(qd):
        _, offset = decode_name(resp, offset)
        offset += 4

    answers = []
    for _ in range(an):
        rname, offset = decode_name(resp, offset)
        rtype, rclass, ttl, rdlen = struct.unpack("!HHIH", resp[offset:offset + 10])
        offset += 10
        rdata = parse_rdata(resp, offset, rdlen, rtype)
        answers.append({
            "name": rname,
            "type": TYPE_REV.get(rtype, str(rtype)),
            "ttl": ttl,
            "data": rdata,
        })
        offset += rdlen

    return {
        "ns": ns_host,
        "ns_ip": ns_ip,
        "name": name,
        "type": qtype,
        "rcode": rcode,
        "answer_count": an,
        "authority_count": ns_count,
        "answers": answers,
    }


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    ns = sys.argv[1]
    name = sys.argv[2]
    qtype = sys.argv[3] if len(sys.argv) > 3 else "A"
    result = query(ns, name, qtype)
    print(json.dumps(result, indent=2))
