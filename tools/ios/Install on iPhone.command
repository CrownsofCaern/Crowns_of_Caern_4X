#!/bin/bash
# Double-click on the Mac: puts the newest Crowns of Caern from GitHub (main) on the
# USB-connected iPhone. Uses a separate clean checkout so local work is never touched.
# Copy this file anywhere (e.g. next to your clone). Settings: ~/.crowns_of_cinder_ios
set -e
REPO_DIR="${CROWNS_IOS_REPO:-$HOME/CrownsOfCaern-ios}"
echo "Updating $REPO_DIR to the newest main..."
cd "$REPO_DIR"
git fetch -q origin main
git checkout -q -f --detach origin/main
bash tools/ios/install_on_iphone.sh
echo
read -n 1 -s -r -p "Press any key to close."
