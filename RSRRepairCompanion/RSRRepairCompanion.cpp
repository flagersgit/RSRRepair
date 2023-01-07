//
//  RSRRepairCompanion.cpp
//  RSRRepairCompanion
//
//  Copyright © 2023 flagers. All rights reserved.
//  Created by flagers on 1/6/23.
//

#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <Headers/kern_util.hpp>
#include <Headers/kern_version.hpp>
#include "RSRRepairCompanion.hpp"

OSDefineMetaClassAndStructors(RSRRepairCompanion, IOService)

RSRRepairCompanion *ADDPR(selfInstance) = nullptr;

IOService *RSRRepairCompanion::probe(IOService *provider, SInt32 *score) {
  ADDPR(selfInstance) = this;
  setProperty("VersionInfo", kextVersion);
  auto service = IOService::probe(provider, score);
  return ADDPR(startSuccess) ? service : nullptr;
}

bool RSRRepairCompanion::start(IOService *provider) {
  ADDPR(selfInstance) = this;
  if (!IOService::start(provider)) {
    SYSLOG("init", "failed to start the parent");
    return false;
  }
  registerService();

  return ADDPR(startSuccess);
}

void RSRRepairCompanion::stop(IOService *provider) {
  ADDPR(selfInstance) = nullptr;
  IOService::stop(provider);
}
