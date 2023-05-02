//
//  UserKernelShared.h
//  RSRRepairCompanion
//
//  Copyright © 2023 flagers. All rights reserved.
//

#ifndef UserKernelShared_h
#define UserKernelShared_h

enum {
  kMethodReportAction,
  
  kNumberOfMethods // Always last
};

enum {
  kReportCanContinue,
  kReportShouldReboot,
  
  kNumberOfReports, // Always second to last
  
  kNoReportYet = 0xff
};

#endif /* UserKernelShared_h */
