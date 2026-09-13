#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x ScreenshotCleanup >/dev/null; then
    printf 'Quit File Cleanup and wait for any cleanup to finish before installing.\n' >&2
    exit 1
fi
bash scripts/build.sh
python3 - <<'PY'
from pathlib import Path
from datetime import datetime
import shutil
import subprocess
home = Path.home()
built = Path.cwd() / '.build/File Cleanup.app'
installed = home / 'Applications/File Cleanup.app'
legacy = home / 'Applications/Screenshot Cleanup.app'
support = home / 'Library/Application Support/Screenshot Cleanup'
backup = support / 'Backups' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
backup.mkdir(parents=True)
installed.parent.mkdir(parents=True, exist_ok=True)
plist = home / 'Library/LaunchAgents/com.nikhlkapadia.cleanup-desktop-screenshots.plist'
if plist.exists(): shutil.copy2(plist, backup / plist.name)
previous_app = installed if installed.exists() else legacy
if previous_app.exists(): shutil.move(str(previous_app), str(backup / previous_app.name))
try:
    subprocess.run(['/usr/bin/ditto', str(built), str(installed)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(installed)], check=True)
    subprocess.run([str(installed / 'Contents/MacOS/ScreenshotCleanup'), '--install-schedule'], check=True)
except Exception:
    if installed.exists(): shutil.move(str(installed), str(backup / 'Failed installation.app'))
    previous = backup / previous_app.name
    if previous.exists(): shutil.move(str(previous), str(previous_app))
    raise
print(f'Installed: {installed}')
print(f'Previous app and schedule: {backup}')
PY
