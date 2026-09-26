#!/usr/bin/env python3
"""Build the bundled exercise library from free-exercise-db (public domain).

Source: https://github.com/yuhonas/free-exercise-db
Output: ios/Form/Resources/exercises.json

Usage: python3 scripts/build_exercises.py [path/to/exercises.json]
With no argument, the dataset is downloaded from GitHub.
"""
import json
import sys
import urllib.request
from pathlib import Path

SOURCE_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
OUT = Path(__file__).resolve().parent.parent / "ios/Form/Resources/exercises.json"

KEEP_CATEGORIES = {"strength", "powerlifting", "olympic weightlifting"}
KEEP_EQUIPMENT = {
    "barbell", "dumbbell", "body only", "cable", "machine",
    "kettlebells", "e-z curl bar", "bands",
}
EQUIPMENT_NAMES = {"body only": "bodyweight", "kettlebells": "kettlebell", "e-z curl bar": "ez bar"}


def load(argv):
    if len(argv) > 1:
        return json.loads(Path(argv[1]).read_text())
    with urllib.request.urlopen(SOURCE_URL) as resp:
        return json.load(resp)


def main(argv):
    raw = load(argv)
    out = []
    for x in raw:
        if x["category"] not in KEEP_CATEGORIES:
            continue
        if x.get("equipment") not in KEEP_EQUIPMENT:
            continue
        if x["level"] == "expert":
            continue
        out.append({
            "id": x["id"],
            "name": x["name"],
            "equipment": EQUIPMENT_NAMES.get(x["equipment"], x["equipment"]),
            "primaryMuscles": x["primaryMuscles"],
            "secondaryMuscles": x["secondaryMuscles"],
            "mechanic": x.get("mechanic"),
            "instructions": x["instructions"],
            "images": x["images"],
        })
    out.sort(key=lambda e: e["name"].lower())
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    print(f"Wrote {len(out)} exercises to {OUT}")


if __name__ == "__main__":
    main(sys.argv)
