#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Hardware smoke test: log in on the board console, run checks, archive the log, print PASS/FAIL per check.

usage: smoke.py [--port /dev/ttyUSB2] [--baud 230400] [--log DIR] [--net HOST] [--sd] [--reset flash|FILE.bit] [--wait SECONDS]

The board must already be running Linux (power cycle, flash boot or SD boot). The log (build/smoke/<time>.log by
default) records the kernel, CPU clock, board register values and every command with its output, which identifies
the board, bitstream (CPU_KHZ, STATUS, ETH clock) and kernel build. Exit status 0 only if every check passed.
"""

import argparse
import os
import re
import subprocess
import sys
import time

import serial

# (name, shell command, regex that must match the output, description of the expectation)
CHECKS = [
    ("kernel", "uname -r", r"^6\.18\.\d+", "Linux 6.18.x"),
    (
        "memory",
        "grep MemTotal /proc/meminfo",
        r"MemTotal:\s+(1[0-9]{6}|[2-9][0-9]{6})",
        "about 1 GiB visible",
    ),
    ("isa", "grep -E '^(isa|mmu)' /proc/cpuinfo", r"rv64ima.*\n.*sv39", "rv64ima with Sv39"),
    (
        "cpu_clock",
        "devmem 0xF800100C 32",
        r"0x0*51615$",
        "CPU_KHZ register (333333 = 0x51615)",
    ),
    ("ddr_status", "devmem 0xF8001008 32", r"0x0*3$", "DDR4 calibrated, ui_clk reset released"),
    (
        "scratch",
        "devmem 0xF8001014 32 0x5A5AA5A5; devmem 0xF8001014 32",
        r"0x5A5AA5A5",
        "scratch register read-back",
    ),
    ("die_temp", "devmem 0xF8001020 32", r"0x0000[0-9A-F]{4}", "SYSMON temperature code present"),
    (
        "interrupts",
        "grep -c -E 'riscv-timer|uartlite' /proc/interrupts",
        r"^2$",
        "timer and UART interrupts registered",
    ),
    (
        "sd_mounts",
        "mount | grep -E ' / | /data '",
        r"/data type ext4 \(rw",
        "root and writable /data",
    ),
    (
        "ds18b20",
        "cat /sys/bus/w1/devices/28-*/w1_slave",
        r"crc=.. YES\n.*t=\d+",
        "1-Wire temperature with a valid CRC",
    ),
    (
        "barometer",
        "cat /sys/bus/iio/devices/iio:device*/in_pressure_input",
        r"^(9\d|10\d)\.\d+",
        "pressure 90-109 kPa",
    ),
    ("fan", "cat /sys/class/hwmon/hwmon*/fan1_input", r"^\d+$", "fan tach readable"),
    (
        "led_loopback",
        "for i in 0 1 2 3 4 5 6 7; do echo 1 >/sys/class/leds/led$i/brightness; "
        "echo $(( ($(devmem 0xF8003000 32) >> 3) & 255 )); echo 0 >/sys/class/leds/led$i/brightness; done",
        r"^1\n2\n4\n8\n16\n32\n64\n128$",
        "each LED output reads back as the only set bit of its GPIO field",
    ),
    (
        "keys_idle",
        "echo $(( $(devmem 0xF8003000 32) & 0x7800 ))",
        r"^0$",
        "no pushbutton pressed (K1-K4 read 0)",
    ),
    (
        "i2c_buses",
        "i2cdetect -l | grep -c xiic; i2cdetect -y -r 1 | grep -E '^50:' | cut -c1-9",
        r"^2\n50: 50 51",
        "two AXI IIC buses; the two BL24C256 EEPROMs answer at 0x50 and 0x51 on bus 1",
    ),
    (
        "dmesg_clean",
        "dmesg | grep -i -E 'oops|bug:|panic|call trace|i/o error|mmc.*error' | head -3; echo end",
        r"^end$",
        "no kernel faults or SD errors",
    ),
]

# Write a random file to /data, flush, drop the page cache, read it back and compare checksums.
SD_CHECKS = [
    (
        "sd_roundtrip",
        "dd if=/dev/urandom of=/data/smoke.bin bs=1M count=16 2>/dev/null && sync && "
        "a=$(md5sum /data/smoke.bin) && echo 3 >/proc/sys/vm/drop_caches && "
        "b=$(md5sum /data/smoke.bin) && rm -f /data/smoke.bin && sync && "
        '[ "$a" = "$b" ] && echo ROUNDTRIP_OK',
        r"^ROUNDTRIP_OK$",
        "16 MiB written to /data and read back identical",
    ),
]

NET_CHECKS = [
    (
        "eth_link",
        "ip -o link show eth0",
        r"<[^>]*LOWER_UP",
        "eth0 up with carrier (LiteEth has no MDIO, so the speed is not readable)",
    ),
]


class Console:
    def __init__(self, port, baud, logf):
        self.s = serial.Serial(port, baud, timeout=0.2)
        self.log = logf

    def send(self, data, chunk=8, gap=0.004):
        """Paced write: the UART lite has a 16-byte RX FIFO and a burst of a whole command line can overrun it while the CPU
        is busy, which drops characters (a lost closing quote then leaves the shell waiting for more input)."""
        for i in range(0, len(data), chunk):
            self.s.write(data[i : i + chunk])
            self.s.flush()
            time.sleep(gap)

    def read_until(self, pattern, timeout):
        buf = b""
        end = time.time() + timeout
        while time.time() < end:
            chunk = self.s.read(4096)
            if chunk:
                buf += chunk
                self.log.write(chunk.decode("latin1"))
                if re.search(pattern, buf.decode("latin1")):
                    return buf.decode("latin1")
        return buf.decode("latin1")

    def login(self, wait):
        """Log in as root. Nothing is sent while the board is still printing: a key during the ROM's 3 s window
        stops the SD boot and drops into the monitor. A newline is sent only after 15 s of silence (prompt already printed)."""
        end = time.time() + wait
        quiet_since = time.time()
        text = ""
        while time.time() < end:
            chunk = self.read_until(r"login: $|# $", 1)
            if chunk:
                text += chunk
                quiet_since = time.time()
                if re.search(r"login: $", text):
                    self.s.write(b"root\n")
                    self.read_until(r"# $", 5)
                    break
                if re.search(r"# $", text):
                    break
            elif time.time() - quiet_since > 15:
                self.s.write(b"\n")
                quiet_since = time.time() - 10
                text = ""
        else:
            return False
        # Without echo the output holds only what the commands print.
        self.s.write(b"stty -echo\n")
        self.read_until(r"# $", 5)
        return True

    def run(self, cmd, timeout=30):
        tag = "__END%d__" % int(time.time() * 1000)
        self.send(("%s; echo %s$?\n" % (cmd, tag)).encode())
        out = self.read_until(r"(?m)^" + tag + r"\d+", timeout).replace("\r", "")
        m = re.search(r"(?m)^" + tag + r"(\d+)", out)
        body = out[: m.start()] if m else out
        return body.strip(), int(m.group(1)) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB2")
    ap.add_argument("--baud", type=int, default=230400)
    ap.add_argument(
        "--log", default=os.path.join(os.path.dirname(__file__), "..", "build", "smoke")
    )
    ap.add_argument("--net", metavar="HOST", help="also check the Ethernet link and ping HOST")
    ap.add_argument("--sd", action="store_true", help="also write/read back a 16 MiB file on /data")
    ap.add_argument(
        "--reset",
        metavar="BITSTREAM|flash",
        help="open the console first, then reconfigure the FPGA ('flash' = from the config flash, "
        "else load the .bit over JTAG) and test the fresh boot",
    )
    ap.add_argument("--wait", type=int, default=120, help="seconds to wait for the login prompt")
    a = ap.parse_args()
    os.makedirs(a.log, exist_ok=True)
    path = os.path.join(a.log, time.strftime("%Y%m%d-%H%M%S") + ".log")
    failed = 0
    with open(path, "w", buffering=1) as logf:
        con = Console(a.port, a.baud, logf)
        if a.reset:
            # The console must already be open when the FPGA restarts: a port opened afterwards can stay silent (seen on this host).
            cmd = ["openFPGALoader", "--cable", "ft232"] + (
                ["-r"] if a.reset == "flash" else [a.reset]
            )
            logf.write("### %s\n" % " ".join(cmd))
            if subprocess.run(cmd, capture_output=True, text=True, check=False).returncode != 0:
                print("FAIL reset: %s" % " ".join(cmd))
                return 1
        if not con.login(a.wait):
            print("FAIL login: no prompt within %d s (log %s)" % (a.wait, path))
            return 1
        checks = list(CHECKS)
        if a.sd:
            checks += SD_CHECKS
        if a.net:
            checks += NET_CHECKS + [
                (
                    "ping",
                    "ping -c 3 -W 2 %s | tail -2" % a.net,
                    r" 0% packet loss",
                    "no loss to " + a.net,
                )
            ]
        for name, cmd, pat, what in checks:
            body, rc = con.run(cmd, 240 if name == "sd_roundtrip" else 30)
            ok = re.search(pat, body, re.M) is not None
            print(
                "%s %s: %s%s"
                % ("PASS" if ok else "FAIL", name, what, "" if ok else "  [got: %r]" % body[:80])
            )
            logf.write("\n### %s rc=%s %s\n" % (name, rc, "PASS" if ok else "FAIL"))
            failed += not ok
    print(
        "%s (%d failed, log %s)"
        % ("SMOKE FAIL" if failed else "SMOKE PASS", failed, os.path.relpath(path))
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
