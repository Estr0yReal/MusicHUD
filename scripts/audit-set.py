#!/usr/bin/env python3
"""Sets one Music HUD setting through cfprefsd.

Writing the plist file directly does not work: cfprefsd caches preferences and
silently ignores out-of-band edits, which once caused an audit run to measure
"HUD hidden" with the HUD on screen.
"""
import json, os, plistlib, subprocess, sys

key, value = sys.argv[1], sys.argv[2]
path = os.path.expanduser('~/Library/Preferences/com.musichud.desktophud.plist')
data = plistlib.load(open(path, 'rb'))
settings = json.loads(data['MusicHUD.settings.v1'].decode())
settings[key] = True if value == 'true' else (False if value == 'false' else (int(value) if value.lstrip('-').isdigit() else value))
blob = json.dumps(settings, separators=(',', ':')).encode()
data['MusicHUD.settings.v1'] = blob
plistlib.dump(data, open(path, 'wb'))
subprocess.run(['defaults', 'write', 'com.musichud.desktophud', 'MusicHUD.settings.v1', '-data', blob.hex()], check=True)
print(f"{key} = {settings[key]}")
