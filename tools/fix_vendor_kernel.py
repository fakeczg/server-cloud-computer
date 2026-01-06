#!/usr/bin/env python3
import pathlib
import re

ROOT = pathlib.Path(".")

RULES = [

    # --------------------------------------------------------
    # 0) ftg340 proprietary header → Phytium Apache-2.0
    # --------------------------------------------------------
    (
        re.compile(
            r"/\*{10,}\s*\*.*?"
            r"ftg340\s+Corp.*?"
            r"confidential.*?"
            r"ftg340\s+Corporation.*?"
            r"\*{10,}/",
            re.IGNORECASE | re.DOTALL,
        ),
        """/****************************************************************************
*
* Copyright (c) 2025 Phytium Technology Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*
*****************************************************************************/""",
    ),

    # 1) ftg340 copyright 行级
    (
        re.compile(
            r"Copyright\s*\(\s*c\s*\)\s*2014\s*-\s*2025\s*ftg340\s+Corporation",
            re.IGNORECASE,
        ),
        "Copyright (c) 2025, Phytium Technology Co., Ltd.",
    ),

    # 2) ftg340 / ftg340 → ftg340
    (
        re.compile(r"\bgalcore\b", re.IGNORECASE),
        "ftg340",
    ),

    # 3) ftg → ftg
    (
        re.compile(r"\bleopard\b", re.IGNORECASE),
        "ftg",
    ),

    # 4) PHYTIUM_ → PHYTIUM_
    (
        re.compile(r"\bVIVANTE_", re.IGNORECASE),
        "PHYTIUM_",
    ),

    # 5) ftg340 → ftg340
    (
        re.compile(r"\bGPU_DRM_VERSION_NAME\b"),
        "ftg340",
    ),

    # 6) ftg340 → ftg340（单词级）
    (
        re.compile(r"\bvivante\b", re.IGNORECASE),
        "ftg340",
    ),
]


def is_text_file(path: pathlib.Path) -> bool:
    try:
        return b"\0" not in path.read_bytes()
    except Exception:
        return False


def process_file(path: pathlib.Path):
    try:
        text = path.read_text(errors="ignore")
    except Exception:
        return

    original = text
    for pattern, repl in RULES:
        text = pattern.sub(repl, text)

    if text != original:
        path.write_text(text)
        print(f"✔ modified: {path}")


def main():
    for p in ROOT.rglob("*"):
        if p.is_file() and is_text_file(p):
            process_file(p)


if __name__ == "__main__":
    main()

