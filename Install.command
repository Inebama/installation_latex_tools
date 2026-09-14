#!/bin/bash
# Double-click this file in Finder to run the installer.
# (macOS opens any executable ".command" file in Terminal.)

cd "$(dirname "$0")" || exit 1

clear
./install.sh "$@"
rc=$?

echo
if [ $rc -eq 0 ]; then
  echo "Finished. You can close this window."
else
  echo "The installer reported a problem (exit $rc)."
  echo "The log file mentioned above has the details."
fi
echo
echo "Press return to close."
read -r _
