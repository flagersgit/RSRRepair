//
//  RSRRepairCompanion.hpp
//  RSRRepairCompanion
//
//  Copyright © 2023 flagers. All rights reserved.
//  Created by flagers on 1/6/23.
//

#ifndef RSRRepairCompanion_hpp
#define RSRRepairCompanion_hpp

class EXPORT RSRRepairCompanion : public IOService {
  OSDeclareDefaultStructors(RSRRepairCompanion)
  
public:
  IOService* probe(IOService *provider, SInt32 *score) APPLE_KEXT_OVERRIDE;
  bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
  void stop(IOService *provider) APPLE_KEXT_OVERRIDE;
};

extern RSRRepairCompanion *ADDPR(selfInstance);

#endif /* RSRRepairCompanion_hpp */
