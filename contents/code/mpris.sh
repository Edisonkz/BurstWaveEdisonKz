#!/usr/bin/env python3
# Emits a single TSV line: PlaybackStatus \t mpris:artUrl \t xesam:title \t xesam:artist
# Picks the first MPRIS player that reports a non-Stopped state, preferring the
# Plasma browser integration (which carries mpris:artUrl for browser tabs).
import json
import subprocess
import sys

PRIORITIES = [
    "org.mpris.MediaPlayer2.plasma-browser-integration",
]


def bus(args):
    try:
        out = subprocess.run(
            ["busctl", "--user", "--json=short"] + args,
            capture_output=True,
            text=True,
            timeout=3,
        ).stdout.strip()
        return out
    except Exception:
        return ""


def prop(player, interface, member):
    raw = bus(["get-property", player, "/org/mpris/MediaPlayer2", interface, member])
    if not raw:
        return None
    try:
        return json.loads(raw).get("data")
    except Exception:
        return None


def to_str(v):
    if isinstance(v, dict):
        return to_str(v.get("data", v))
    if isinstance(v, list):
        return ", ".join(to_str(x) for x in v)
    return str(v) if v is not None else ""


def main():
    players = []
    try:
        names = json.loads(bus(["list"]))
        if isinstance(names, dict):
            names = names.get("data", names)
        if isinstance(names, list):
            players = [n.get("name", "") for n in names]
    except Exception:
        players = []

    mpris = [p for p in players if str(p).startswith("org.mpris.MediaPlayer2.")]

    seen = set()
    ordered = []
    # Prioritarios primero, luego el resto en orden de aparición
    for p in [p for p in PRIORITIES if p in mpris]:
        ordered.append(p)
        seen.add(p)
    for p in mpris:
        if p not in seen:
            ordered.append(p)
            seen.add(p)

    fallback = None
    for p in ordered:
        status = to_str(prop(p, "org.mpris.MediaPlayer2.Player", "PlaybackStatus"))
        meta = prop(p, "org.mpris.MediaPlayer2.Player", "Metadata") or {}
        if status == "" and not meta:
            continue
        if status == "Stopped" and "xesam:title" not in meta:
            continue

        art = to_str(meta.get("mpris:artUrl"))
        title = to_str(meta.get("xesam:title"))
        artist = to_str(meta.get("xesam:artist"))

        if art:
            print("%s\t%s\t%s\t%s" % (status, art, title, artist))
            return 0
        elif fallback is None and (title or artist):
            fallback = (status, "", title, artist)

    if fallback:
        print("%s\t%s\t%s\t%s" % fallback)
        return 0

    print("\t\t\t")
    return 0


if __name__ == "__main__":
    sys.exit(main())