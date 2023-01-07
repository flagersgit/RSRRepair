#!/bin/bash

#  getCdhash.sh
#  RSRRepair
#
#  Copyright © 2023 flagers. All rights reserved.
#  Created by flagers on 1/6/23.
#  

codesignOutput=$(codesign -dvvv ${TARGET_BUILD_DIR}/RSRRepair 2>&1 >/dev/null)

while read -r line; do
  if [[ $line =~ ^CDHash=.* ]]; then
    eval $line
  fi
done <<< "$codesignOutput"

if [ "$CONFIGURATION" == "Release" ]; then
  echo Determined CDHash: $CDHash
fi

printf $CDHash | xxd -r -p | xxd -i -n cdhashBytes > ${TARGET_BUILD_DIR}/cdhash.h
  
if [ "$CONFIGURATION" == "Debug" ]; then
  /usr/libexec/PlistBuddy -c 'Import ":IOKitPersonalities:RSRRepairCompanion:RSRRepairCDHash" /dev/stdin' "${TARGET_BUILD_DIR}/RSRRepairCompanion.kext/Contents/Info.plist" <<< "$(printf $CDHash | xxd -r -p)"
fi
