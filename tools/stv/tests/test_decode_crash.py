import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import decode_crash


class DecodeCrashTests(unittest.TestCase):
    def test_decodes_complete_sh2_context(self):
        values = [0x10000000 + index for index in range(decode_crash.RAW_WORDS)]
        block = struct.pack(
            f">{2 + decode_crash.RAW_WORDS}I",
            decode_crash.MAGIC, decode_crash.RAW_WORDS, *values)
        data = bytearray(0x1000)
        offset = decode_crash.CRASH_ADDRESS - decode_crash.HWRAM_BASE
        data[offset:offset + len(block)] = block

        result = decode_crash.decode(data)
        self.assertEqual(result["VBR"], values[0])
        self.assertEqual(result["R14"], values[5])
        self.assertEqual(result["R0"], values[19])
        self.assertEqual(result["PC"], values[20])
        self.assertEqual(result["SR"], values[21])

    def test_rejects_missing_magic(self):
        with self.assertRaisesRegex(ValueError, "crash magic"):
            decode_crash.decode(bytes(0x1000))


if __name__ == "__main__":
    unittest.main()
