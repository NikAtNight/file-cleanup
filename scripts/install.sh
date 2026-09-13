#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x ScreenshotCleanup >/dev/null; then
    printf 'Quit Screenshot Cleanup and wait for any cleanup to finish before installing.\n' >&2
    exit 1
fi
bash scripts/build.sh
python3 - <<'PY'
from pathlib import Path
from datetime import datetime
import shutil
import subprocess
home = Path.home()
built = Path.cwd() / '.build/Screenshot Cleanup.app'
installed = home / 'Applications/Screenshot Cleanup.app'
support = home / 'Library/Application Support/Screenshot Cleanup'
backup = support / 'Backups' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
backup.mkdir(parents=True)
installed.parent.mkdir(parents=True, exist_ok=True)
plist = home / 'Library/LaunchAgents/com.nikhlkapadia.cleanup-desktop-screenshots.plist'
if plist.exists(): shutil.copy2(plist, backup / plist.name)
if installed.exists(): shutil.move(str(installed), str(backup / installed.name))
try:
    subprocess.run(['/usr/bin/ditto', str(built), str(installed)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(installed)], check=True)
    subprocess.run([str(installed / 'Contents/MacOS/ScreenshotCleanup'), '--install-schedule'], check=True)
except Exception:
    if installed.exists(): shutil.move(str(installed), str(backup / 'Failed installation.app'))
    previous = backup / installed.name
    if previous.exists(): shutil.move(str(previous), str(installed))
    raise
print(f'Installed: {installed}')
print(f'Previous app and schedule: {backup}')
PY
