#!/bin/bash

#  package.tool
#  RSRRepair
#
#  Copyright © 2023 flagers. All rights reserved.
#  Created by flagers on 1/6/23.
#  

if [ "${TARGET_BUILD_DIR}" = "" ]; then
  echo "This cannot be run outside of Xcode"
  exit 1
fi

cd "${TARGET_BUILD_DIR}"

mkdir -p package/Tools || exit 1
mkdir -p package/Kexts || exit 1

cd package || exit 1

cp ../RSRRepair Tools/ || exit 1
for kext in ../*.kext; do
  echo "$kext"
  cp -a "$kext" Kexts/ || exit 1
done

if [ "$CONFIGURATION" = "" ]; then
  if [ "$(basename "$TARGET_BUILD_DIR")" = "Debug" ]; then
    CONFIGURATION="Debug"
  else
    CONFIGURATION="Release"
  fi
fi

if [ "$CONFIGURATION" = "Release" ]; then
  mkdir -p dSYM || exit 1
  for dsym in ../*.dSYM; do
    if [ "$dsym" = "../*.dSYM" ]; then
      continue
    fi
    echo "$dsym"
    cp -a "$dsym" dSYM/ || exit 1
  done
fi

archive="RSRRepair-${MODULE_VERSION}-$(echo $CONFIGURATION | tr /a-z/ /A-Z/).zip"
zip -qry -FS ../"${archive}" * || exit 1
