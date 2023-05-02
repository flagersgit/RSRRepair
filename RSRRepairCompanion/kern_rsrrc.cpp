//
//  kern_rsrrc.cpp
//  RSRRepairCompanion
//
//  Copyright © 2023 flagers. All rights reserved.
//  Created by flagers on 1/6/23.
//

// Lilu headers
#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
// Kernel SDK headers
#include <IOKit/IOPlatformExpert.h>
#include <kern/cs_blobs.h>
// Project headers
#include "kern_rsrrc.hpp"

static UInt64 userspaceReport = kNoReportYet;
static mach_vm_address_t orgValidateKCUUIDFromPrelinkInfo {};
int wrapValidateKCUUIDFromPrelinkInfo(uuid_t *loaded_kcuuid, kc_kind_t type, OSDictionary *infoDict, const char *uuid_key) {
  int kcReturn = FunctionCast(wrapValidateKCUUIDFromPrelinkInfo, orgValidateKCUUIDFromPrelinkInfo)(loaded_kcuuid, type, infoDict, uuid_key);

  for (int loops = 0; userspaceReport == kNoReportYet; loops++) {
    SYSLOG(MODULE_SHORT, "%s: looped %i times; waiting 2 seconds", __FUNCTION__, loops);
    IOSleep(2000);
    if (loops == 15)
      break;
  }
  if (userspaceReport == kReportShouldReboot) {
    SYSLOG(MODULE_SHORT, "%s: restarting now", __FUNCTION__);
    PEHaltRestart(kPERestartCPU);
  } else {
    SYSLOG(MODULE_SHORT, "%s: continuing boot", __FUNCTION__);
  }
  
  return kcReturn;
}

#pragma mark - Plugin start
static void pluginStart() {
  DBGLOG(MODULE_SHORT, "start");
  
  lilu.onPatcherLoadForce([](void *user, KernelPatcher &patcher) {
    RSRRepairClient::solveNeededSymbols(patcher);
    KernelPatcher::RouteRequest csRoute = KernelPatcher::RouteRequest("__ZN6OSKext29validateKCUUIDfromPrelinkInfoEPA16_h7kc_kindP12OSDictionaryPKc", wrapValidateKCUUIDFromPrelinkInfo, orgValidateKCUUIDFromPrelinkInfo);
          if (!patcher.routeMultipleLong(KernelPatcher::KernelID, &csRoute, 1))
                SYSLOG(MODULE_SHORT, "failed to route KC UUID validation function");
  });
};

// Boot args.
static const char *bootargOff[] {
  "-rsrrcoff"
};
static const char *bootargDebug[] {
  "-rsrrcdbg"
};
static const char *bootargBeta[] {
  "-rsrrcbeta"
};

// Plugin configuration.
PluginConfiguration ADDPR(config) {
  xStringify(PRODUCT_NAME),
  parseModuleVersion(xStringify(MODULE_VERSION)),
  LiluAPI::AllowNormal,
  bootargOff,
  arrsize(bootargOff),
  bootargDebug,
  arrsize(bootargDebug),
  bootargBeta,
  arrsize(bootargBeta),
  KernelVersion::Ventura,
  KernelVersion::Ventura,
  pluginStart
};

OSDefineMetaClassAndStructors(RSRRepairClient, super)

void *(*RSRRepairClient::_get_bsdtask_info)(task_t) = nullptr;
UInt8 *(*RSRRepairClient::_cs_get_cdhash)(proc_t) = nullptr;
/* static */
bool RSRRepairClient::solveNeededSymbols(KernelPatcher &patcher) {
  _get_bsdtask_info = reinterpret_cast<decltype(_get_bsdtask_info)>(patcher.solveSymbol(KernelPatcher::KernelID, "_get_bsdtask_info"));
  _cs_get_cdhash = reinterpret_cast<decltype(_cs_get_cdhash)>(patcher.solveSymbol(KernelPatcher::KernelID, "_cs_get_cdhash"));
  if (!(_get_bsdtask_info && _cs_get_cdhash)) {
    SYSLOG(MODULE_SHORT, "could not solve required symbols: %s %s", _get_bsdtask_info ? "" : xStringify(_get_bsdtask_info), _cs_get_cdhash ? "" : xStringify(_cs_get_cdhash));
    return false;
  }
  return true;
}

bool RSRRepairClient::start(IOService *provider) {
  if (!super::start(provider)) {
    SYSLOG(MODULE_SHORT, "super::start() returned false");
    return false;
  }
  
  if (!(_get_bsdtask_info && _cs_get_cdhash)) {
    SYSLOG(MODULE_SHORT, "cannot start RSRRepairClient without required symbols: %s %s", _get_bsdtask_info ? "" : xStringify(_get_bsdtask_info), _cs_get_cdhash ? "" : xStringify(_cs_get_cdhash));
    return false;
  }
  
  this->provider = provider;
  
  return true;
}

void RSRRepairClient::stop(IOService *provider) {
  super::stop(provider);
}

bool RSRRepairClient::initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties) {
  bool allowed = false;
  if (!owningTask)
    return false;
  
  // Verify identity of task opening this user client.
  proc_t proc = (proc_t)_get_bsdtask_info(owningTask);
  SYSLOG_COND(!proc, MODULE_SHORT, "failed to get proc for owningTask");
  DBGLOG_COND(proc, MODULE_SHORT, "got proc for owningTask");
  if (!proc)
    return false;
  
  UInt8 *procCdhash = _cs_get_cdhash(proc);
  SYSLOG_COND(!proc, MODULE_SHORT, "failed to get procCdhash for proc");
  DBGLOG_COND(proc, MODULE_SHORT, "got procCdhash for proc");
  if (!procCdhash)
    return false;
  
  if (!memcmp(&cdhashBytes, procCdhash, CS_CDHASH_LEN)) {
    DBGLOG(MODULE_SHORT, "approved; CDHash matches internal hash");
    allowed = true;
  }

#ifdef DEBUG
  OSData *cdhash = OSDynamicCast(OSData, provider->getProperty("RSRRepair CDHash"));
  
  SYSLOG_COND(!cdhash, MODULE_SHORT, "failed to get CDHash from provider");
  DBGLOG_COND(cdhash, MODULE_SHORT, "got CDHash from provider");
  if (!cdhash)
    return false;
  
  if (cdhash->isEqualTo(procCdhash, CS_CDHASH_LEN)) {
    DBGLOG(MODULE_SHORT, "approved; CDHash matches Info.plist hash");
    allowed = true;
  }
#endif
  
  if (!super::initWithTask(owningTask, securityToken, type))
    return false;
  
  this->owningTask = owningTask;
  
  return allowed;
}

/* static */
const IOExternalMethodDispatch RSRRepairClient::sMethods[kNumberOfMethods] = {
  { // kMethodReportAction
    reinterpret_cast<IOExternalMethodAction>(&RSRRepairClient::methodReportAction),
    1 /* checkScalarInputCount     */,
    0 /* checkStructureInputSize   */,
    0 /* checkScalarOutputCount    */,
    0 /* checkStructureOutputSize  */
  }
};

IOReturn RSRRepairClient::externalMethod(uint32_t selector, IOExternalMethodArguments *arguments, IOExternalMethodDispatch *dispatch, OSObject *target, void *reference) {
  if (selector >= kNumberOfMethods)
    return kIOReturnUnsupported;
  
  dispatch = const_cast<IOExternalMethodDispatch *>(&sMethods[selector]);
  
  target = provider;
  reference = this;
  
  return super::externalMethod(selector, arguments, dispatch, target, reference);
}

/* static */
IOReturn RSRRepairClient::methodReportAction(IOService *target, void *ref, IOExternalMethodArguments *args) {
  if (args->scalarInputCount != sMethods[kMethodReportAction].checkScalarInputCount)
    return kIOReturnBadArgument;
  
  if (args->scalarInput[0] > kNumberOfReports)
    return kIOReturnBadArgument;
  
  userspaceReport = args->scalarInput[0];
  
  return kIOReturnSuccess;
}
