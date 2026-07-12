import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pack_bakubaku as pack


class PackBakuBakuTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.payloads = {}
        for file_index, (name, size, _) in enumerate(pack.ROMS):
            pattern = bytes(((i + file_index * 37) & 0xFF for i in range(256)))
            data = (pattern * ((size + 255) // 256))[:size]
            (self.directory / name).write_bytes(data)
            self.payloads[name] = data

    def tearDown(self):
        self.temp.cleanup()

    def test_mame_layout_and_hardware_manifest(self):
        image, manifest = pack.build_image(self.directory, verify_hashes=False)
        fpr = self.payloads["fpr17969.13"]

        self.assertEqual(len(image), 0x02000000)
        self.assertEqual(image[0:0x20:2], bytes(0x10))
        self.assertEqual(image[1:0x21:2], fpr[:0x10])
        self.assertEqual(image[0x0200000:0x0200020], fpr[:0x20])
        self.assertEqual(image[0x0300000:0x0300020], fpr[:0x20])

        for index, name in enumerate(("mpr17970.2", "mpr17971.3",
                                      "mpr17972.4", "mpr17973.5")):
            offset = 0x0400000 + index * 0x0400000
            source = self.payloads[name]
            self.assertEqual(image[offset:offset + 8],
                             bytes((source[1], source[0], source[3], source[2],
                                    source[5], source[4], source[7], source[6])))

        self.assertEqual(image[0x1400000:], bytes(0x0C00000))
        self.assertEqual(manifest["image_sha1"], hashlib.sha1(image).hexdigest())
        self.assertEqual(manifest["hardware_windows"][1]["chip_select"], "CS1")
        self.assertEqual(manifest["required_relocation"]["replacement"],
                         "0x04000000-0x04ffffff")

    def test_wrong_size_is_rejected(self):
        path = self.directory / "fpr17969.13"
        path.write_bytes(path.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, "size"):
            pack.build_image(self.directory, verify_hashes=False)

    def test_boot_overlay_is_embedded_at_31mb(self):
        overlay = b"SEGA SEGASATURN " + bytes(range(64))
        image, manifest = pack.build_image(
            self.directory, verify_hashes=False, boot_overlay=overlay)
        self.assertEqual(image[0x01F00000:0x01F00000 + len(overlay)], overlay)
        self.assertTrue(manifest["boot_overlay"]["enabled"])
        self.assertEqual(manifest["boot_overlay"]["sha1"],
                         hashlib.sha1(overlay).hexdigest())

    def test_invalid_boot_overlay_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "hardware ID"):
            pack.build_image(self.directory, verify_hashes=False,
                             boot_overlay=b"not a Saturn header")
        with self.assertRaisesRegex(ValueError, "exceeds"):
            pack.build_image(self.directory, verify_hashes=False,
                             boot_overlay=b"SEGA SEGASATURN " + bytes(0x1000))

    def test_noncanonical_hash_is_rejected_by_default(self):
        with self.assertRaisesRegex(ValueError, "SHA-1"):
            pack.build_image(self.directory)


if __name__ == "__main__":
    unittest.main()
