#import "utils.h"
#import <Foundation/Foundation.h>
#import "CoreServices.h"

#import <spawn.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <dlfcn.h>

void enumerateProcessesUsingBlock(void (^enumerator)(pid_t pid, NSString* executablePath, BOOL* stop)) {
    static int maxArgumentSize = 0;
    if (maxArgumentSize == 0) {
        size_t size = sizeof(maxArgumentSize);
        if (sysctl((int[]){ CTL_KERN, KERN_ARGMAX }, 2, &maxArgumentSize, &size, NULL, 0) == -1) {
            perror("sysctl argument size");
            maxArgumentSize = 4096; // Default
        }
    }
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    struct kinfo_proc *info;
    size_t length;
    int count;
    
    if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0)
        return;
    if (!(info = malloc(length)))
        return;
    if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
        free(info);
        return;
    }
    count = length / sizeof(struct kinfo_proc);
    for (int i = 0; i < count; i++) {
        @autoreleasepool {
            pid_t pid = info[i].kp_proc.p_pid;
            if (pid == 0) {
                continue;
            }
            size_t size = maxArgumentSize;
            char* buffer = (char *)malloc(length);
            if (sysctl((int[]){ CTL_KERN, KERN_PROCARGS2, pid }, 3, buffer, &size, NULL, 0) == 0) {
                NSString* executablePath = [NSString stringWithCString:(buffer+sizeof(int)) encoding:NSUTF8StringEncoding];
                
                BOOL stop = NO;
                enumerator(pid, executablePath, &stop);
                if(stop) {
                    free(buffer);
                    break;
                }
            }
            free(buffer);
        }
    }
    free(info);
}

int fd_is_valid(int fd) {
    return fcntl(fd, F_GETFD) != -1 || errno != EBADF;
}

void printMultilineNSString(NSString* stringToPrint) {
    NSCharacterSet *separator = [NSCharacterSet newlineCharacterSet];
    NSArray* lines = [stringToPrint componentsSeparatedByCharactersInSet:separator];
    for(NSString* line in lines) {
        NSLog(@"%@", line);
    }
}

NSString* getNSStringFromFile(int fd) {
    NSMutableString* ms = [NSMutableString new];
    ssize_t num_read;
    char c;
    if(!fd_is_valid(fd)) return @"";
    while((num_read = read(fd, &c, sizeof(c)))) {
        [ms appendString:[NSString stringWithFormat:@"%c", c]];
        if(c == '\n') break;
    }
    return ms.copy;
}

BOOL isRemovableSystemApp(NSString* appId) {
    return [[NSFileManager defaultManager] fileExistsAtPath:[@"/System/Library/AppSignatures" stringByAppendingPathComponent:appId]];
}

NSArray* mineekStoreInstalledAppContainerPaths() {
    NSMutableArray* appContainerPaths = [NSMutableArray new];

    NSString* appContainersPath = @"/var/containers/Bundle/Application";

    NSError* error;
    NSArray* containers = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appContainersPath error:&error];
    if(error) {
        NSLog(@"error getting app bundles paths %@", error);
    }
    if(!containers) return nil;
    
    for(NSString* container in containers) {
        NSString* containerPath = [appContainersPath stringByAppendingPathComponent:container];
        BOOL isDirectory = NO;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:containerPath isDirectory:&isDirectory];
        if(exists && isDirectory) {
            NSString* mineekStoreMark = [containerPath stringByAppendingPathComponent:@"_MineekStore"];
            if([[NSFileManager defaultManager] fileExistsAtPath:mineekStoreMark]) {
                NSString* mineekStoreApp = [containerPath stringByAppendingPathComponent:@"MineekStore.app"];
                if(![[NSFileManager defaultManager] fileExistsAtPath:mineekStoreApp]) {
                    [appContainerPaths addObject:containerPath];
                }
            }
        }
    }

    return appContainerPaths.copy;
}

NSArray* mineekStoreInstalledAppBundlePaths() {
    NSMutableArray* appPaths = [NSMutableArray new];
    for(NSString* containerPath in mineekStoreInstalledAppContainerPaths()) {
        NSArray* items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:containerPath error:nil];
        if(!items) return nil;
        
        for(NSString* item in items) {
            if([item.pathExtension isEqualToString:@"app"]) {
                [appPaths addObject:[containerPath stringByAppendingPathComponent:item]];
            }
        }
    }
    return appPaths.copy;
}

NSString* mineekStorePath() {
    NSError* mcmError;
    MCMAppContainer* appContainer = [MCMAppContainer containerWithIdentifier:@"com.mineek.MineekStore" createIfNecessary:NO existed:NULL error:&mcmError];
    if(!appContainer) return nil;
    return appContainer.url.path;
}

NSString* mineekStoreAppPath() {
    return [mineekStorePath() stringByAppendingPathComponent:@"MineekStore.app"];
}

void killall(NSString* processName, BOOL softly) {
    enumerateProcessesUsingBlock(^(pid_t pid, NSString* executablePath, BOOL* stop) {
        if([executablePath.lastPathComponent isEqualToString:processName]) {
            if(softly) {
                kill(pid, SIGTERM);
            } else {
                kill(pid, SIGKILL);
            }
        }
    });
}

SecStaticCodeRef getStaticCodeRef(NSString *binaryPath) {
    if(binaryPath == nil) {
        return NULL;
    }
    
    CFURLRef binaryURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)binaryPath, kCFURLPOSIXPathStyle, false);
    if(binaryURL == NULL) {
        NSLog(@"[getStaticCodeRef] failed to get URL to binary %@", binaryPath);
        return NULL;
    }
    
    SecStaticCodeRef codeRef = NULL;
    OSStatus result;
    
    result = SecStaticCodeCreateWithPathAndAttributes(binaryURL, kSecCSDefaultFlags, NULL, &codeRef);
    
    CFRelease(binaryURL);
    
    if(result != errSecSuccess) {
        NSLog(@"[getStaticCodeRef] failed to create static code for binary %@", binaryPath);
        return NULL;
    }
        
    return codeRef;
}

NSDictionary* dumpEntitlements(SecStaticCodeRef codeRef) {
    if(codeRef == NULL) {
        NSLog(@"[dumpEntitlements] attempting to dump entitlements without a StaticCodeRef");
        return nil;
    }
    
    CFDictionaryRef signingInfo = NULL;
    OSStatus result;
    
    result = SecCodeCopySigningInformation(codeRef, kSecCSRequirementInformation, &signingInfo);
    
    if(result != errSecSuccess) {
        NSLog(@"[dumpEntitlements] failed to copy signing info from static code");
        return nil;
    }
    
    NSDictionary *entitlementsNSDict = nil;
    
    CFDictionaryRef entitlements = CFDictionaryGetValue(signingInfo, kSecCodeInfoEntitlementsDict);
    if(entitlements == NULL) {
        NSLog(@"[dumpEntitlements] no entitlements specified");
    } else if(CFGetTypeID(entitlements) != CFDictionaryGetTypeID()) {
        NSLog(@"[dumpEntitlements] invalid entitlements");
    } else {
        entitlementsNSDict = (__bridge NSDictionary *)(entitlements);
        NSLog(@"[dumpEntitlements] dumped %@", entitlementsNSDict);
    }
    
    CFRelease(signingInfo);
    return entitlementsNSDict;
}

NSDictionary* dumpEntitlementsFromBinaryAtPath(NSString *binaryPath) {
    // This function is intended for one-shot checks. Main-event functions should retain/release their own SecStaticCodeRefs
    
    if(binaryPath == nil) {
        return nil;
    }
    
    SecStaticCodeRef codeRef = getStaticCodeRef(binaryPath);
    if(codeRef == NULL) {
        return nil;
    }
    
    NSDictionary *entitlements = dumpEntitlements(codeRef);
    CFRelease(codeRef);

    return entitlements;
}

NSDictionary* dumpEntitlementsFromBinaryData(NSData* binaryData) {
    NSDictionary* entitlements;
    NSString* tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSURL* tmpURL = [NSURL fileURLWithPath:tmpPath];
    if([binaryData writeToURL:tmpURL options:NSDataWritingAtomic error:nil]) {
        entitlements = dumpEntitlementsFromBinaryAtPath(tmpPath);
        [[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];
    }
    return entitlements;
}
