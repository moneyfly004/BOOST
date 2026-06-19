#!/usr/bin/env python3
import struct
import sys
from pathlib import Path


ICNS_ENTRIES = [
    ("icp4", "app_icon_16.png", 16, 16),
    ("ic11", "app_icon_16@2x.png", 32, 32),
    ("icp5", "app_icon_32.png", 32, 32),
    ("ic12", "app_icon_64.png", 64, 64),
    ("ic07", "app_icon_128.png", 128, 128),
    ("ic13", "app_icon_128@2x.png", 256, 256),
    ("ic08", "app_icon_256.png", 256, 256),
    ("ic14", "app_icon_256@2x.png", 512, 512),
    ("ic09", "app_icon_512.png", 512, 512),
    ("ic10", "app_icon_1024.png", 1024, 1024),
]

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def read_png_with_size(path: Path, expected_width: int, expected_height: int) -> bytes:
    data = path.read_bytes()
    if len(data) < 24 or not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        raise ValueError(f"{path} is not a valid PNG")

    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (expected_width, expected_height):
        raise ValueError(
            f"{path} must be {expected_width}x{expected_height}, got {width}x{height}"
        )
    return data


def rebuild_icns(source_iconset: Path, output_file: Path) -> None:
    chunks = []
    for icon_type, filename, width, height in ICNS_ENTRIES:
        data = read_png_with_size(source_iconset / filename, width, height)
        chunks.append(icon_type.encode("ascii") + struct.pack(">I", len(data) + 8) + data)

    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_bytes(
        b"icns" + struct.pack(">I", 8 + sum(len(chunk) for chunk in chunks)) + b"".join(chunks)
    )


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: rebuild_macos_icns.py <AppIcon.appiconset> <output.icns>", file=sys.stderr)
        return 2

    rebuild_icns(Path(sys.argv[1]), Path(sys.argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
