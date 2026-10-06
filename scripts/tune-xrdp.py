#!/usr/bin/env python3
"""Apply low-latency keys to xrdp.ini, confined to the [Globals] and [Xorg]
sections. Line-based so comments and unrelated sections are never mangled:

  * an existing key (commented or active) in the target section is rewritten
    in place, keeping the file tidy;
  * a missing key is inserted right after the section header;
  * duplicates within the section are collapsed to one.

Usage: tune-xrdp.py [path-to-xrdp.ini]   (default: /etc/xrdp/xrdp.ini)
"""
import re
import sys

# [Globals] — these cut interactive latency / CPU per frame.
GLOBALS = {
    "tcp_nodelay": "true",        # keystrokes leave immediately (no Nagle delay)
    "tcp_keepalive": "true",
    "bitmap_cache": "true",
    "bitmap_compression": "true",
    "bulk_compression": "true",
    "max_bpp": "32",
    "new_cursors": "true",
    "use_fastpath": "both",       # fastpath I/O, outside the slow channel path
    "crypt_level": "low",         # the Tailscale link is already encrypted
    "security_layer": "negotiate",
}

# [Xorg] — frame-capture interval in ms. Defaults are 16/32/40; we cut them
# for snappier UI (higher = less bandwidth, more perceived latency).
XORG = {
    "rfx_frame_interval": "16",
    "h264_frame_interval": "16",
    "normal_frame_interval": "16",
}

KEY_RE = re.compile(r"^[#;]?\s*([A-Za-z0-9_]+)\s*=")


def set_in_section(lines, section, wanted):
    hdr = next((i for i, ln in enumerate(lines) if ln.strip() == section), None)
    if hdr is None:
        return lines, False
    end = len(lines)
    for j in range(hdr + 1, len(lines)):
        if lines[j].lstrip().startswith("["):
            end = j
            break

    out, placed = [], set()
    for ln in lines[hdr + 1:end]:
        m = KEY_RE.match(ln)
        if m and m.group(1) in wanted:
            key = m.group(1)
            if key in placed:
                continue  # collapse duplicate
            out.append(f"{key}={wanted[key]}")
            placed.add(key)
        else:
            out.append(ln)

    missing = [f"{k}={v}" for k, v in wanted.items() if k not in placed]
    return lines[:hdr + 1] + missing + out + lines[end:], True


def main(path):
    with open(path) as fh:
        lines = fh.read().splitlines()
    lines, ok_g = set_in_section(lines, "[Globals]", GLOBALS)
    lines, ok_x = set_in_section(lines, "[Xorg]", XORG)
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"xrdp.ini tuned (Globals={ok_g}, Xorg={ok_x})")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/etc/xrdp/xrdp.ini")
