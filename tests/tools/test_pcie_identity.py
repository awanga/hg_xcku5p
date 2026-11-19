# SPDX-License-Identifier: MIT
"""Tests for tools/pcie_identity.py and tools/cfg_time.py. Expected values are written out by hand from the PCI and lspci formats, not computed by the tool."""

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import pcie_identity as pi  # noqa: E402

GOOD = """\
01:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:9034]
\tSubsystem: Xilinx Corporation Device [10ee:0007]
\tFlags: bus master, fast devsel, latency 0
\tRegion 0: Memory at f7000000 (32-bit, non-prefetchable) [size=64K]
"""
OTHER = "00:1f.2 SATA controller [0106]: Intel Corporation Device [8086:a102] (rev 31)\n\tSubsystem: Dell Device [1028:0749]\n"


class Identity(unittest.TestCase):
    def setUp(self):
        self.d = pi.load()

    def test_manifest_values(self):
        d = self.d
        self.assertEqual((d["vendor_id"], d["device_id"]), (0x10EE, 0x9034))
        self.assertEqual((d["subsystem_vendor_id"], d["subsystem_id"]), (0x10EE, 0x0007))
        self.assertEqual((d["class_code"], d["revision_id"]), (0x058000, 0))

    def test_generics_layout(self):
        g = pi.generics(self.d)
        self.assertEqual(g["PCI_ID"], 0x903410EE)  # {device, vendor}
        self.assertEqual(g["PCI_CLASS"], 0x05800000)  # {class[23:0], revision}
        self.assertEqual(g["PCI_SUBSYS"], 0x000710EE)  # {subsystem, subsystem vendor}

    def test_generics_other_values(self):
        d = {
            "vendor_id": 0x1234,
            "device_id": 0xABCD,
            "subsystem_vendor_id": 0x5678,
            "subsystem_id": 0x9ABC,
            "class_code": 0x070001,
            "revision_id": 0x03,
        }
        g = pi.generics(d)
        self.assertEqual(g["PCI_ID"], 0xABCD1234)
        self.assertEqual(g["PCI_CLASS"], 0x07000103)
        self.assertEqual(g["PCI_SUBSYS"], 0x9ABC5678)

    def test_lspci_match(self):
        self.assertEqual(pi.check_lspci(self.d, GOOD), [])

    def test_lspci_with_other_devices_first(self):
        self.assertEqual(pi.check_lspci(self.d, OTHER + GOOD), [])

    def test_lspci_absent(self):
        bad = pi.check_lspci(self.d, OTHER)
        self.assertEqual(len(bad), 1)
        self.assertIn("did not enumerate", bad[0])

    def test_lspci_wrong_class(self):
        bad = pi.check_lspci(self.d, GOOD.replace("[0580]", "[0700]"))
        self.assertTrue(any("class 0700" in b for b in bad), bad)

    def test_lspci_wrong_subsystem(self):
        bad = pi.check_lspci(self.d, GOOD.replace("[10ee:0007]", "[10ee:0008]"))
        self.assertTrue(any("subsystem" in b for b in bad), bad)

    def test_lspci_wrong_revision(self):
        bad = pi.check_lspci(
            self.d, GOOD.replace("Device [10ee:9034]", "Device [10ee:9034] (rev 02)", 1)
        )
        self.assertTrue(any("revision 02" in b for b in bad), bad)

    def test_lspci_needs_vv(self):
        bad = pi.check_lspci(self.d, GOOD.split("\n")[0] + "\n")
        self.assertTrue(any("subsystem IDs not found" in b for b in bad), bad)

    def _ip(self, **over):
        v = {
            "VENDOR_ID": "10EE",
            "DEVICE_ID": "9034",
            "SUBSYSTEM_VENDOR_ID": "10EE",
            "SUBSYSTEM_ID": "0007",
            "CLASS_CODE": "058000",
            "REVISION_ID": "00",
        }
        v.update(over)
        body = (
            f"    .PF0_CLASS_CODE(24'H{v['CLASS_CODE']}),\n    .PF0_VENDOR_ID(16'H{v['VENDOR_ID']}),\n    .PF0_DEVICE_ID(16'H{v['DEVICE_ID']}),\n"
            f"    .PF0_REVISION_ID(8'H{v['REVISION_ID']}),\n    .PF0_SUBSYSTEM_VENDOR_ID(16'H{v['SUBSYSTEM_VENDOR_ID']}),\n    .PF0_SUBSYSTEM_ID(16'H{v['SUBSYSTEM_ID']}),\n"
        )
        tmp = tempfile.mkdtemp()
        d = pathlib.Path(tmp) / "x" / "ip_0" / "synth"
        d.mkdir(parents=True)
        (d / "x_pcie4_ip.v").write_text(body)
        return tmp

    def test_ip_match(self):
        self.assertEqual(pi.check_ip(self.d, self._ip()), [])

    def test_ip_class_mismatch(self):
        bad = pi.check_ip(self.d, self._ip(CLASS_CODE="070001"))
        self.assertEqual(len(bad), 1)
        self.assertIn("PF0_CLASS_CODE = 070001", bad[0])

    def test_ip_device_mismatch(self):
        self.assertEqual(len(pi.check_ip(self.d, self._ip(DEVICE_ID="9011"))), 1)

    def test_ip_missing(self):
        self.assertIn("no generated", pi.check_ip(self.d, tempfile.mkdtemp())[0])

    def test_missing_key(self):
        with tempfile.NamedTemporaryFile("w", suffix=".cfg", delete=False) as f:
            f.write("vendor_id 10EE\n")
        with self.assertRaises(SystemExit):
            pi.load(f.name)
        os.unlink(f.name)


class HostCheck(unittest.TestCase):
    def fake(self, ids=None, words=None, resource=True):
        ids = ids or {}
        words = words or {}
        root = pathlib.Path(tempfile.mkdtemp())
        dev = root / "0000:01:00.0"
        dev.mkdir()
        v = {
            "vendor": 0x10EE,
            "device": 0x9034,
            "subsystem_vendor": 0x10EE,
            "subsystem_device": 0x0007,
            "class": 0x058000,
        }
        v.update(ids)
        for k, val in v.items():
            (dev / k).write_text("0x%06x\n" % val if k == "class" else "0x%04x\n" % val)
        if resource:
            img = bytearray(0x2000)
            w = {0x1000: 0x43415244, 0x1010: 0x903410EE, 0x1014: 0x05800000, 0x1018: 0x000710EE}
            w.update(words)
            for off, val in w.items():
                img[off : off + 4] = val.to_bytes(4, "little")
            (dev / "resource0").write_bytes(bytes(img))
        return str(root)

    def test_ok(self):
        self.assertEqual(pi.host_check(pi.load(), "0000:01:00.0", self.fake()), [])

    def test_not_enumerated(self):
        self.assertIn("not enumerated", pi.host_check(pi.load(), "0000:02:00.0", self.fake())[0])

    def test_wrong_class(self):
        bad = pi.host_check(pi.load(), "0000:01:00.0", self.fake(ids={"class": 0x070001}))
        self.assertTrue(any(b.startswith("class 700") for b in bad), bad)

    def test_image_from_other_identity(self):
        bad = pi.host_check(pi.load(), "0000:01:00.0", self.fake(words={0x1010: 0x901110EE}))
        self.assertEqual(len(bad), 1)
        self.assertIn("PCI_ID 901110ee", bad[0])

    def test_not_a_card_image(self):
        bad = pi.host_check(pi.load(), "0000:01:00.0", self.fake(words={0x1000: 0xFFFFFFFF}))
        self.assertTrue(any("not a card image" in b for b in bad), bad)

    def test_no_resource0(self):
        bad = pi.host_check(pi.load(), "0000:01:00.0", self.fake(resource=False))
        self.assertTrue(any("resource0" in b for b in bad), bad)


class CfgTime(unittest.TestCase):
    def run_tool(self, size, *args):
        with tempfile.NamedTemporaryFile(suffix=".bit", delete=False) as f:
            f.write(b"\0" * size)
        try:
            return subprocess.run(
                [sys.executable, str(ROOT / "tools" / "cfg_time.py"), f.name, *args],
                capture_output=True,
                text=True,
            )
        finally:
            os.unlink(f.name)

    def test_over_budget(self):
        r = self.run_tool(5_100_000, "--strict")  # 40.8 Mbit / (4 x 51 MHz) = 200 ms
        self.assertEqual(r.returncode, 1)
        self.assertIn(">= 200 ms", r.stdout)
        self.assertIn("OVER BUDGET", r.stdout)

    def test_within_budget(self):
        r = self.run_tool(1_275_000, "--strict")  # 10.2 Mbit / 204 Mbit/s = 50 ms
        self.assertEqual(r.returncode, 0)
        self.assertIn(">= 50 ms", r.stdout)
        self.assertIn("within budget", r.stdout)

    def test_not_strict_never_fails(self):
        self.assertEqual(self.run_tool(5_100_000).returncode, 0)


if __name__ == "__main__":
    unittest.main()
