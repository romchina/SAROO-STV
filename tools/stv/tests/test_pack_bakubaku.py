import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pack_bakubaku as pack
import verify_saroo_image as verify_image


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

    def test_native_hle_is_embedded_at_cs1_offset(self):
        hle = bytes((i * 29) & 0xFF for i in range(192))
        image, manifest = pack.build_image(
            self.directory, verify_hashes=False, native_hle=hle)
        self.assertEqual(image[0x01400000:0x01400000 + len(hle)], hle)
        self.assertTrue(manifest["native_hle"]["enabled"])
        self.assertEqual(manifest["native_hle"]["saturn_start"], "0x04400000")
        self.assertEqual(manifest["native_hle"]["sha1"],
                         hashlib.sha1(hle).hexdigest())

    def test_oversize_native_hle_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "exceeds"):
            pack.build_image(self.directory, verify_hashes=False,
                             native_hle=bytes(0x10001))

    def test_noncanonical_hash_is_rejected_by_default(self):
        with self.assertRaisesRegex(ValueError, "SHA-1"):
            pack.build_image(self.directory)

    def test_packed_hardware_image_verifier(self):
        overlay = b"SEGA SEGASATURN " + bytes(range(64))
        hle = bytes((i * 29) & 0xFF for i in range(192))
        image, manifest = pack.build_image(
            self.directory, verify_hashes=False,
            boot_overlay=overlay, native_hle=hle)
        image_path = self.directory / "candidate.bin"
        manifest_path = self.directory / "candidate.bin.json"
        overlay_path = self.directory / "trampoline.bin"
        hle_path = self.directory / "native-hle.bin"
        image_path.write_bytes(image)
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        overlay_path.write_bytes(overlay)
        hle_path.write_bytes(hle)

        result = verify_image.verify(
            image_path, manifest_path, overlay_path, hle_path)
        self.assertEqual(result["image_sha1"], hashlib.sha1(image).hexdigest())

        manifest["image_sha1"] = "0" * 40
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "image SHA-1"):
            verify_image.verify(
                image_path, manifest_path, overlay_path, hle_path)


if __name__ == "__main__":
    unittest.main()
