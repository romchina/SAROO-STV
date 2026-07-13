import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "stv-trampoline" / "profile_flags.py"
SPEC = importlib.util.spec_from_file_location("profile_flags", SCRIPT)
profile_flags = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(profile_flags)


class TrampolineProfileTests(unittest.TestCase):
    def test_shienryu_descriptor_drives_assembler_values(self):
        descriptor = json.loads((
            ROOT / "tools" / "stv" / "games" / "shienryu.json"
        ).read_text(encoding="utf-8"))
        flags = profile_flags.assembler_flags(descriptor)
        joined = " ".join(flags)
        self.assertIn("GAME_DST=0x06003000", joined)
        self.assertIn("GAME_SRC=0x02200000", joined)
        self.assertIn("GAME_LONG_COUNT=0x0003E400", joined)
        self.assertIn("GAME_FIRST_WORD=0x53454741", joined)

    def test_copy_length_must_be_long_aligned(self):
        descriptor = {"boot_profile": {
            "destination": "0x06003000",
            "source_saturn_address": "0x02200000",
            "length": 3,
            "first_word": "0x53454741",
        }}
        with self.assertRaisesRegex(ValueError, "multiple of four"):
            profile_flags.assembler_flags(descriptor)


if __name__ == "__main__":
    unittest.main()
