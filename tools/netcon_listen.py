#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Print kernel netconsole datagrams (UDP) with a timestamp: tools/netcon_listen.py [port] [seconds]."""

import socket
import sys
import time

port = int(sys.argv[1]) if len(sys.argv) > 1 else 6666
limit = float(sys.argv[2]) if len(sys.argv) > 2 else 600
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("", port))
s.settimeout(1)
end = time.time() + limit
while time.time() < end:
    try:
        data, addr = s.recvfrom(4096)
    except socket.timeout:
        continue
    print("%s %s" % (time.strftime("%H:%M:%S"), data.decode(errors="replace").rstrip()), flush=True)
