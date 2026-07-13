import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import analyze_boot_profile
import pack_game


class BootProfileAnalysisTests(unittest.TestCase):
    def test_compare_boot_copy_reports_runtime_changes(self):
        image = bytearray(pack_game.IMAGE_SIZE)
        source = 0x200000
        payload = bytes(range(64))
        image[source:source + len(payload)] = payload
        hwram = bytearray(analyze_boot_profile.HWRAM_SIZE)
        destination = 0x3000
        hwram[destination:destination + len(payload)] = payload
        hwram[destination + 10] ^= 0xFF
        descriptor = {
            "game": "fixture",
            "boot_profile": {
                "source_image_offset": source,
                "destination": "0x06003000",
                "length": len(payload),
            },
        }

        result = analyze_boot_profile.compare_boot_copy(
            descriptor, bytes(image), bytes(hwram))

        self.assertEqual(result["equal_bytes"], 63)
        self.assertEqual(result["modified_bytes"], 1)
        self.assertEqual(result["longest_equal_run"], 53)


if __name__ == "__main__":
    unittest.main()
