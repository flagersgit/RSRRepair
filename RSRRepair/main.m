//
//  main.m
//  RSRRepair
//
//  Copyright © 2023 flagers. All rights reserved.
//

#import <Foundation/Foundation.h>

#include <mach-o/loader.h>
#include <IOKit/IOKitLib.h>
#include <libproc.h>
#include "UserKernelShared.h"

#define SYSVOL_BOOTKC "/System/Library/KernelCollections/BootKernelExtensions.kc"
#define SYSVOL_SYSKC "/System/Library/KernelCollections/SystemKernelExtensions.kc"
#define DATAVOL_AUXKC "/Library/KernelCollections/AuxiliaryKernelExtensions.kc"

void installToRcServer(void) {
    NSLog(@"- Installing RSRRepair to /etc/rc.server.");
    char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
    int ret = proc_pidpath([[NSProcessInfo processInfo] processIdentifier], pathBuffer, sizeof(pathBuffer));
    if (ret <= 0) {
        NSLog(@"- | Failed to resolve RSRRepair installer path.");
        NSLog(@"- | You may copy RSRRepair binary to /etc/rc.server manually.");
    } else {
        NSTask *task    = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/ditto";
        task.arguments  = [NSArray arrayWithObjects:[NSString stringWithUTF8String:pathBuffer], @"/etc/rc.server", nil];
        [task launch];
        [task waitUntilExit];
        
        task            = [[NSTask alloc] init];
        task.launchPath = @"/bin/chmod";
        task.arguments  = [NSArray arrayWithObjects:@"+x", @"/etc/rc.server", nil];
        [task launch];
        [task waitUntilExit];
    }
}

NSString* getApfsPrebootUUID(void) {
    io_registry_entry_t IODTchosen = IORegistryEntryFromPath(kIOMasterPortDefault, "IODeviceTree:/chosen");
    if (!IODTchosen)
        return NULL;
    
    CFDataRef cfDataPrebootUUID = (CFDataRef)IORegistryEntryCreateCFProperty(IODTchosen, CFSTR("apfs-preboot-uuid"), kCFAllocatorDefault, 0);
    NSString *prebootUUID = [NSString stringWithUTF8String:(const char *)CFDataGetBytePtr(cfDataPrebootUUID)];
    
    if (!cfDataPrebootUUID || !prebootUUID)
        return NULL;
    
    return prebootUUID;
}

static uint64_t kernelReport = kNoReportYet;

NSDictionary *processKCAtPath(NSString *path) {
    NSDictionary *kcPrelinkInfoDict = NULL;
    struct mach_header_64 mh;
    
    FILE *fhandle = fopen([path UTF8String], "rb");
    if (!fhandle) {
        NSLog(@"RSRRepair: Failed to open '%@' with error: %s", path, strerror(errno));
        return kcPrelinkInfoDict;
    }
    fread(&mh, sizeof(struct mach_header_64), 1, fhandle);
    
    if (mh.magic != MH_MAGIC_64 || mh.cputype != CPU_TYPE_X86_64 || mh.cpusubtype != CPU_SUBTYPE_X86_64_ALL || mh.filetype != MH_FILESET) {
        NSLog(@"RSRRepair: Invalid Mach-O at '%@'", path);
        return kcPrelinkInfoDict;
    }
    
    struct load_command *lcmds = (struct load_command *)malloc(mh.sizeofcmds);
    fread(lcmds, mh.sizeofcmds, 1, fhandle);
    
    uint32_t ncmds = mh.ncmds;
    struct load_command *lcmd = lcmds;
    
    char *prelinkInfoPlist = NULL;
    for (uint32_t i = 0; i < ncmds; i++) {
        switch (lcmd->cmd) {
            case LC_SEGMENT_64: {
                struct segment_command_64 *lcmd_seg64 = (struct segment_command_64 *)lcmd;
                if (!memcmp(lcmd_seg64->segname, "__PRELINK_INFO", sizeof(lcmd_seg64->segname))) {
                    if (lcmd_seg64->nsects == 1) {
                        struct section_64 *sect64 = (struct section_64 *)((char *)(lcmd_seg64) + sizeof(struct segment_command_64));
                        char infoSectName[16] = "__info";
                        if (!memcmp(sect64->sectname, &infoSectName, sizeof(sect64->sectname))) {
                            prelinkInfoPlist = malloc(sect64->size);
                            fseek(fhandle, sect64->offset, SEEK_SET);
                            fread(prelinkInfoPlist, sect64->size, 1, fhandle);
                            NSData *plistData = [NSData dataWithBytesNoCopy:prelinkInfoPlist length:sect64->size freeWhenDone:NO];
                            NSError *errorDesc = nil;
                            kcPrelinkInfoDict = [NSPropertyListSerialization
                                                propertyListWithData:plistData
                                                options:NSPropertyListMutableContainersAndLeaves
                                                format:nil
                                                error:&errorDesc];
                        }
                    }
                }
            } break;
        }
        
        lcmd = (struct load_command *)((char *)(lcmd) + lcmd->cmdsize);
    }
    
    if (prelinkInfoPlist)
        free(prelinkInfoPlist);
    free(lcmds);
    return kcPrelinkInfoDict;
}

void syncPrebootKC(NSString *prebootPath, NSString *systemPath) {
    NSTask *task    = [[NSTask alloc] init];
    task.launchPath = @"/bin/cp";
    task.arguments  = [NSArray arrayWithObjects:@"-f", @"-v", systemPath, prebootPath, nil];
    [task launch];
    [task waitUntilExit];
    
    if ([task terminationStatus] == 0) {
        NSLog(@"RSRRepair: Succeeded in re-syncing Preboot BootKC.");
        kernelReport = kReportShouldReboot;
    } else {
        for (int i = 0; i < 10; i++) {
            NSLog(@"RSRRepair: Failed to re-sync Preboot BootKC. Please manually re-sync the BootKC from Single User Mode or recoveryOS.");
            kernelReport = kReportCanContinue;
        }
    }
}

void deleteAuxKC(void) {
    NSTask *task    = [[NSTask alloc] init];
    task.launchPath = @"/bin/rm";
    task.arguments  = [NSArray arrayWithObjects:@"-f", @"-v", @"/Library/KernelCollections/AuxiliaryKernelExtensions.kc", nil];
    [task launch];
    [task waitUntilExit];
    
    if ([task terminationStatus] == 0) {
        NSLog(@"RSRRepair: Succeeded in deleting AuxKC");
        kernelReport = kReportShouldReboot;
    } else {
        for (int i = 0; i < 10; i++) {
            NSLog(@"RSRRepair: Failed to delete AuxKC. Please manually delete the AuxKC from Single User Mode or recoveryOS.");
            kernelReport = kReportCanContinue;
        }
    }
}

void reportToKernelspace(uint64_t report) {
    if (report == kReportShouldReboot)
        NSLog(@"RSRRepair: Restarting macOS after syncing BootKC artifacts.");
    if (report == kReportCanContinue)
        NSLog(@"RSRRepair: Allowing RSRRepairCompanion to continue.");
    
    io_connect_t dataPort;
      
    CFMutableDictionaryRef dict = IOServiceMatching("RSRRepairCompanion");
      
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, dict);
      
    if (!service) {
        if (report == kReportShouldReboot)
            NSLog(@"Could not locate RSRRepairCompanion. Please reboot manually.");
        if (report == kReportCanContinue)
            NSLog(@"Could not locate RSRRepairCompanion. Will continue after 30 seconds.");
        return;
    }
      
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &dataPort);
      
    IOObjectRelease(service);
    
    uint64_t scalarInput[1] = { report };
    kr = IOConnectCallScalarMethod(dataPort, kMethodReportAction, scalarInput, 1, NULL, NULL);
    if (kr != KERN_SUCCESS) {
        NSLog(@"RSRRepair: Failed to call kMethodReportAction in kernelspace companion.");
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (geteuid()) {
            NSLog(@"Please run RSRRepair as root.");
            return 1;
        }
        
        NSArray *arguments = [[NSProcessInfo processInfo] arguments];
        if (arguments.count > 1) {
            if ([arguments[1] isEqualToString:@"--install"]) {
                NSLog(@"Starting RSRRepair installation...");
                installToRcServer();
            }
        } else {
            NSString *dataVolAuxKCPath = @DATAVOL_AUXKC;
            NSString *sysVolSysKCPath = @SYSVOL_SYSKC;
            NSString *sysVolBootKCPath = @SYSVOL_BOOTKC;
            NSString *prebootBootKCPath = [NSString stringWithFormat: @"/System/Volumes/Preboot/%@/boot%@", getApfsPrebootUUID(), @SYSVOL_BOOTKC];
            
            /*
            NSDictionary *dataVolAuxKCInfo = processKCAtPath(dataVolAuxKCPath);
            NSDictionary *sysVolSysKCInfo = processKCAtPath(sysVolSysKCPath);
            */
            NSDictionary *sysVolBootKCInfo = processKCAtPath(sysVolBootKCPath);
            NSDictionary *prebootBootKCInfo = processKCAtPath(prebootBootKCPath);
            
            // Ensure Preboot BootKC is synced with System BootKC
            if (prebootBootKCInfo && sysVolBootKCInfo) {
                if (![prebootBootKCInfo[@"_PrelinkKCID"] isEqualToData:sysVolBootKCInfo[@"_PrelinkKCID"]]) {
                    NSLog(@"RSRRepair: Preboot BootKC is out of sync with System BootKC. Syncing...");
                    syncPrebootKC(prebootBootKCPath, sysVolBootKCPath);
                    reportToKernelspace(kernelReport);
                } else {
                    NSLog(@"RSRRepair: Preboot BootKC is in sync with System BootKC.");
                    reportToKernelspace(kReportCanContinue);
                }
            }
        }
    }
}
