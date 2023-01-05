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
    task.arguments  = [NSArray arrayWithObjects:@"-f", systemPath, prebootPath, nil];
    [task launch];
    [task waitUntilExit];
}

void restartSystem(void) {
  NSLog(@"RSRRepair: Restarting macOS after syncing BootKC artifacts.");

  char *restartArgs[] = {
    "/sbin/shutdown",
    "-r",
    "now",
    "RSRRepair is rebooting.",
    NULL
  };

  // This should never return.
  int ret = execv(restartArgs[0], restartArgs);
  if (ret == -1) {
    NSLog(@"RSRRepair: Failed to execute %s", restartArgs[0]);
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
            NSString *prebootBootKCPath = [NSString stringWithFormat: @"/System/Volume/Preboot/%@/boot%@", getApfsPrebootUUID(), @SYSVOL_BOOTKC];
            
            NSDictionary *dataVolAuxKCInfo = processKCAtPath(dataVolAuxKCPath);
            NSDictionary *sysVolSysKCInfo = processKCAtPath(sysVolSysKCPath);
            NSDictionary *sysVolBootKCInfo = processKCAtPath(sysVolBootKCPath);
            NSDictionary *prebootBootKCInfo = processKCAtPath(prebootBootKCPath);
            
            // Ensure Preboot BootKC is synced with System BootKC
            if (prebootBootKCInfo && sysVolBootKCInfo) {
                if (![prebootBootKCInfo[@"_PrelinkKCID"] isEqualToData:sysVolBootKCInfo[@"_PrelinkKCID"]]) {
                    NSLog(@"RSRRepair: Preboot BootKC is out of sync with System BootKC. Syncing...");
                    syncPrebootKC(prebootBootKCPath, sysVolBootKCPath);
                    restartSystem();
                } else {
                    NSLog(@"RSRRepair: Preboot BootKC is in sync with System BootKC.");
                }
            }
        }
    }
}
