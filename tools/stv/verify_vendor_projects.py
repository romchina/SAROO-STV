#!/usr/bin/env python3
"""Check that vendor project files contain the SAROO-STV implementation."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def normalized(path: str) -> str:
    return path.replace("\\", "/").lower().lstrip("./")


def verify_keil() -> None:
    project = ROOT / "Firm_MCU" / "ssmaster.uvprojx"
    tree = ET.parse(project)
    paths = {
        normalized(node.text or "")
        for node in tree.iter()
        if node.tag.rsplit("}", 1)[-1] == "FilePath"
    }
    required = {
        "saturn/stv_rom.c",
        "saturn/stv_menu.c",
    }
    missing = sorted(required - paths)
    if missing:
        raise ValueError(f"Keil project missing ST-V sources: {missing}")
    for relative in required:
        if not (ROOT / "Firm_MCU" / relative).is_file():
            raise ValueError(f"Keil source path does not exist: {relative}")


def verify_quartus() -> None:
    project = ROOT / "FPGA" / "SSMaster.qsf"
    text = project.read_text(encoding="utf-8", errors="replace")
    if not re.search(r"set_global_assignment\s+-name\s+TOP_LEVEL_ENTITY\s+SSMaster", text):
        raise ValueError("Quartus project top-level entity is not SSMaster")
    files = {
        normalized(match.group(1).strip('"'))
        for match in re.finditer(
            r"set_global_assignment\s+-name\s+VERILOG_FILE\s+(\S+|\"[^\"]+\")",
            text,
        )
    }
    required = {"ssmaster.v", "memhub.v", "cachebus.v", "cacheblk.v", "tsdram.v"}
    missing = sorted(required - files)
    if missing:
        raise ValueError(f"Quartus project missing RTL sources: {missing}")
    for relative in required:
        if not (ROOT / "FPGA" / relative).is_file():
            raise ValueError(f"Quartus source path does not exist: {relative}")


def main() -> int:
    verify_keil()
    verify_quartus()
    print("verified Keil ST-V sources and Quartus RTL project membership")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
