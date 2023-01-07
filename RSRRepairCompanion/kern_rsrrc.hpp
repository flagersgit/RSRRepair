//
//  kern_rsrrc.hpp
//  RSRRepairCompanion
//
//  Copyright © 2023 flagers. All rights reserved.
//  Created by flagers on 1/6/23.
//

#ifndef kern_rsrrc_hpp
#define kern_rsrrc_hpp

// Lilu headers
#include <Headers/kern_api.hpp>
// Kernel SDK headers
#include <IOKit/IOUserClient.h>
// Project headers
#include "UserKernelShared.h"

#define MODULE_SHORT "rsrrc"
#define super IOUserClient

class RSRRepairClient : public IOUserClient {
  OSDeclareDefaultStructors(RSRRepairClient)

private:
  IOService *provider;
  task_t owningTask;
  static const IOExternalMethodDispatch sMethods[kNumberOfMethods];
  static void *(*_get_bsdtask_info)(task_t);
  static UInt8 *(*_cs_get_cdhash)(proc_t);
  
public:
  static bool solveNeededSymbols(KernelPatcher &patcher);
  bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
  void stop(IOService *provider) APPLE_KEXT_OVERRIDE;
  bool initWithTask(task_t owningTask, void *securityToken,
                    UInt32 type, OSDictionary *properties) APPLE_KEXT_OVERRIDE;
  IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *arguments,
                          IOExternalMethodDispatch *dispatch, OSObject *target,
                          void *reference) APPLE_KEXT_OVERRIDE;
  
  // IOUserClient Methods
  static IOReturn methodDoReboot(IOService *target, void *ref,
                                 IOExternalMethodArguments *args);
};

#endif /* kern_rsrrc_hpp */
