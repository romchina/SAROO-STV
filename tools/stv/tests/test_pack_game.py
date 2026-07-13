import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pack_game


class DescriptorPackerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        games = Path(pack_game.__file__).with_name("games")
        self.shienryu = pack_game.load_descriptor(games / "shienryu.json")
        self.payloads = {}
        entries = self.shienryu["roms"] + self.shienryu["auxiliary"]
        for index, entry in enumerate(entries):
            size = entry["size"]
            pattern = bytes(((byte + index * 43) & 0xFF for byte in range(256)))
            data = (pattern * ((size + 255) // 256))[:size]
            (self.directory / entry["name"]).write_bytes(data)
            self.payloads[entry["name"]] = data

    def tearDown(self):
        self.temp.cleanup()

    def test_shienryu_mame_layout_and_eeprom_boundary(self):
        image, manifest = pack_game.build_image(
            self.shienryu, self.directory, verify_hashes=False)
        self.assertEqual(len(image), pack_game.IMAGE_SIZE)
        self.assertEqual(image[:0x200000], bytes(0x200000))
        for name, offset in (("mpr19631.7", 0x200000),
                             ("mpr19632.2", 0x400000),
                             ("mpr19633.3", 0x800000)):
            source = self.payloads[name]
            self.assertEqual(
                image[offset:offset + 8],
                bytes((source[1], source[0], source[3], source[2],
                       source[5], source[4], source[7], source[6])))
        self.assertEqual(image[0xC00000:], bytes(0x1400000))
        self.assertEqual(manifest["format"], "saroo-stv-cart-v2")
        self.assertEqual(manifest["game"], "shienryu")
        self.assertEqual(manifest["port_status"], "hardware-candidate")
        self.assertIsNone(manifest["required_relocation"])
        profile = manifest["boot_profile"]
        self.assertEqual(profile["source_image_offset"], 0x200000)
        self.assertEqual(profile["destination"], "0x06003000")
        self.assertEqual(profile["length"], 0xF9000)
        self.assertEqual(profile["entry"], "0x06004010")
        self.assertFalse(profile["requires_stv_bios_resident"])
        resident = self.shienryu["resident_profile"]
        self.assertEqual(
            resident["handler_slots"]["0x06000a00"], "0x06004632")
        self.assertEqual(
            resident["handler_slots"]["0x06000a08"], "0x000044fc")
        self.assertEqual(manifest["resident_profile"], resident)
        self.assertEqual(resident["backup_channel"], 4)
        self.assertEqual(resident["backup_logical_base"], "0x20183d00")
        self.assertEqual(resident["backup_length"], 0x5F4)
        eeprom = manifest["auxiliary"]["eeprom-shienryu.bin"]
        self.assertEqual(eeprom["kind"], "93c46-eeprom")
        self.assertFalse(eeprom["implemented"])
        self.assertEqual(eeprom["sha1"], hashlib.sha1(
            self.payloads["eeprom-shienryu.bin"]).hexdigest())

    def test_hardware_candidate_accepts_boot_modules(self):
        overlay = b"SEGA SEGASATURN " + bytes(32)
        hle = bytes(range(32))
        image, manifest = pack_game.build_image(
            self.shienryu, self.directory, verify_hashes=False,
            boot_overlay=overlay, native_hle=hle)
        self.assertEqual(
            image[pack_game.OVERLAY_OFFSET:
                  pack_game.OVERLAY_OFFSET + len(overlay)], overlay)
        self.assertEqual(
            image[pack_game.HLE_OFFSET:pack_game.HLE_OFFSET + len(hle)], hle)
        self.assertEqual(manifest["port_status"], "hardware-candidate")

    def test_descriptor_rejects_overlapping_operations(self):
        descriptor = {
            "format": "saroo-stv-game-v1",
            "game": "overlap",
            "image_size": pack_game.IMAGE_SIZE,
            "roms": [{
                "name": "a.bin", "size": 4, "sha1": "0" * 40,
                "operations": [
                    {"type": "copy", "offset": 0},
                    {"type": "copy", "offset": 2},
                ],
            }],
        }
        (self.directory / "a.bin").write_bytes(bytes(4))
        with self.assertRaisesRegex(ValueError, "overlaps"):
            pack_game.build_image(
                descriptor, self.directory, verify_hashes=False)

    def test_descriptor_rejects_boot_profile_outside_hwram(self):
        descriptor = dict(self.shienryu)
        descriptor["boot_profile"] = dict(descriptor["boot_profile"])
        descriptor["boot_profile"]["destination"] = "0x060ff000"
        path = self.directory / "bad-profile.json"
        path.write_text(__import__("json").dumps(descriptor), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "exceeds HWRAM"):
            pack_game.load_descriptor(path)


if __name__ == "__main__":
    unittest.main()
