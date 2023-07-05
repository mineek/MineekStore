#import "main.h"
#import <utils.h>
#import <Foundation/Foundation.h>
#import "CoreServices.h"
#import "unarchive.h"
#import "uicache.h"

#import <spawn.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <dlfcn.h>

typedef CFPropertyListRef (*_CFPreferencesCopyValueWithContainerType)(CFStringRef key, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName, CFStringRef containerPath);
typedef void (*_CFPreferencesSetValueWithContainerType)(CFStringRef key, CFPropertyListRef value, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName, CFStringRef containerPath);
typedef Boolean (*_CFPreferencesSynchronizeWithContainerType)(CFStringRef applicationID, CFStringRef userName, CFStringRef hostName, CFStringRef containerPath);
typedef CFArrayRef (*_CFPreferencesCopyKeyListWithContainerType)(CFStringRef applicationID, CFStringRef userName, CFStringRef hostName, CFStringRef containerPath);
typedef CFDictionaryRef (*_CFPreferencesCopyMultipleWithContainerType)(CFArrayRef keysToFetch, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName, CFStringRef containerPath);

int installApp(NSString* appPackagePath, BOOL sign) {
    NSString* appPayloadPath = [appPackagePath stringByAppendingPathComponent:@"Payload"];

    NSString* appBundleToInstallPath = findAppPathInBundlePath(appPayloadPath);
    if(!appBundleToInstallPath) return 167;

    NSString* appId = appIdForAppPath(appBundleToInstallPath);
    if(!appId) return 176;
    if(!infoDictionaryForAppPath(appBundleToInstallPath)) return 172;

    applyPatchesToInfoDictionary(appBundleToInstallPath);

    if(sign) {
        int signRet = signApp(appBundleToInstallPath);
        if(signRet != 0) return signRet;
    }

    MCMAppContainer* appContainer = [MCMAppContainer containerWithIdentifier:appId createIfNecessary:NO existed:nil error:nil];
    if(appContainer) {
        // App update
        // Replace existing bundle with new version

        // Check if the existing app bundle is empty
        NSURL* bundleContainerURL = appContainer.url;
        NSURL* appBundleURL = findAppURLInBundleURL(bundleContainerURL);

        NSURL* mineekStoreMarkURL = [bundleContainerURL URLByAppendingPathComponent:@"_MineekStore"];
        if(appBundleURL && ![mineekStoreMarkURL checkResourceIsReachableAndReturnError:nil]) {
            NSLog(@"[installApp] already installed and not a MineekStore app... bailing out");
            return 171;
        }

        // Terminate app if it's still running
        BKSTerminateApplicationForReasonAndReportWithDescription(appId, 5, false, @"MineekStoreHelper: updating app");

        NSLog(@"[installApp] replacing existing app with new version");

        // Delete existing .app directory if it exists
        if(appBundleURL) {
            [[NSFileManager defaultManager] removeItemAtURL:appBundleURL error:nil];
        }

        NSString* newAppBundlePath = [bundleContainerURL.path stringByAppendingPathComponent:appBundleToInstallPath.lastPathComponent];
        NSLog(@"[installApp] new app path: %@", newAppBundlePath);

        // Install new version into existing app bundle
        NSError* copyError;
        BOOL suc = [[NSFileManager defaultManager] copyItemAtPath:appBundleToInstallPath toPath:newAppBundlePath error:&copyError];
        if(!suc) {
            NSLog(@"[installApp] Error copying new version during update: %@", copyError);
            return 178;
        }
    } else {
        // Initial app install
        BOOL systemMethodSuccessful = NO;
        
        // System method
        // Do initial placeholder installation using LSApplicationWorkspace
        NSLog(@"[installApp] doing placeholder installation using LSApplicationWorkspace");

        // The installApplication API (re)moves the app bundle, so in order to be able to later
        // fall back to the custom method, we need to make a temporary copy just for using it on this API once
        // Yeah this sucks, but there is no better solution unfortunately
        NSError* tmpCopyError;
        NSString* lsAppPackageTmpCopy = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        if(![[NSFileManager defaultManager] copyItemAtPath:appPackagePath toPath:lsAppPackageTmpCopy error:&tmpCopyError]) {
            NSLog(@"failed to make temporary copy of app packge: %@", tmpCopyError);
            return 170;
        }

        NSError* installError;
        @try {
            systemMethodSuccessful = [[LSApplicationWorkspace defaultWorkspace] installApplication:[NSURL fileURLWithPath:lsAppPackageTmpCopy] withOptions:@{
                LSInstallTypeKey : @1,
                @"PackageType" : @"Placeholder"
            } error:&installError];
        } @catch(NSException* e) {
            NSLog(@"[installApp] encountered expection %@ while trying to do placeholder install", e);
            systemMethodSuccessful = NO;
        }

        if(!systemMethodSuccessful) {
            NSLog(@"[installApp] encountered error %@ while trying to do placeholder install", installError);
        }

        [[NSFileManager defaultManager] removeItemAtPath:lsAppPackageTmpCopy error:nil];

        if(!systemMethodSuccessful) {
            // Custom method
            // Manually create app bundle via MCM apis and move app there
            NSLog(@"[installApp] doing custom installation using MCMAppContainer");

            NSError* mcmError;
            appContainer = [MCMAppContainer containerWithIdentifier:appId createIfNecessary:YES existed:nil error:&mcmError];

            if(!appContainer || mcmError) {
                NSLog(@"[installApp] failed to create app container for %@: %@", appId, mcmError);
                return 170;
            } else {
                NSLog(@"[installApp] created app container: %@", appContainer);
            }

            NSString* newAppBundlePath = [appContainer.url.path stringByAppendingPathComponent:appBundleToInstallPath.lastPathComponent];
            NSLog(@"[installApp] new app path: %@", newAppBundlePath);
            
            NSError* copyError;
            BOOL suc = [[NSFileManager defaultManager] copyItemAtPath:appBundleToInstallPath toPath:newAppBundlePath error:&copyError];
            if(!suc) {
                NSLog(@"[installApp] Failed to copy app bundle for app %@, error: %@", appId, copyError);
                return 178;
            }
        }
    }

    appContainer = [MCMAppContainer containerWithIdentifier:appId createIfNecessary:NO existed:nil error:nil];

    NSURL* mineekStoreMarkURL = [appContainer.url URLByAppendingPathComponent:@"_MineekStore"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:mineekStoreMarkURL.path]) {
        NSError* creationError;
        NSData* emptyData = [NSData data];
        BOOL marked = [emptyData writeToURL:mineekStoreMarkURL options:0 error:&creationError];
        if(!marked) {
            NSLog(@"[installApp] failed to mark %@ as MineekStore app by creating %@, error: %@", appId, mineekStoreMarkURL.path, creationError);
            return 177;
        }
    }

    // At this point the (new version of the) app is installed but still needs to be registered
    // Also permissions need to be fixed
    NSURL* updatedAppURL = findAppURLInBundleURL(appContainer.url);
    fixPermissionsOfAppBundle(updatedAppURL.path);
    registerPath(updatedAppURL.path, 0, YES);
    return 0;
}

int installIpa(NSString* ipaPath) {
	cleanRestrictions();

	if(![[NSFileManager defaultManager] fileExistsAtPath:ipaPath]) return 166;

	BOOL suc = NO;
	NSString* tmpPackagePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
	
	suc = [[NSFileManager defaultManager] createDirectoryAtPath:tmpPackagePath withIntermediateDirectories:NO attributes:nil error:nil];
	if(!suc) return 1;

	int extractRet = extract(ipaPath, tmpPackagePath);
	if(extractRet != 0) {
		[[NSFileManager defaultManager] removeItemAtPath:tmpPackagePath error:nil];
		return 168;
	}

	int ret = installApp(tmpPackagePath, YES);
	
	[[NSFileManager defaultManager] removeItemAtPath:tmpPackagePath error:nil];

	return ret;
}


NSString* findAppPathInBundlePath(NSString* bundlePath) {
    NSString* appName = findAppNameInBundlePath(bundlePath);
    if(!appName) return nil;
    return [bundlePath stringByAppendingPathComponent:appName];
}

NSString* appPathForAppId(NSString* appId) {
    if(!appId) return nil;
    for(NSString* appPath in mineekStoreInstalledAppBundlePaths()) {
        if([appIdForAppPath(appPath) isEqualToString:appId])
        {
            return appPath;
        }
    }
    return nil;
}

NSString* findAppNameInBundlePath(NSString* bundlePath) {
    NSArray* bundleItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundlePath error:nil];
    for(NSString* bundleItem in bundleItems) {
        if([bundleItem.pathExtension isEqualToString:@"app"]) {
            return bundleItem;
        }
    }
    return nil;
}

NSDictionary* infoDictionaryForAppPath(NSString* appPath) {
    if(!appPath) return nil;
    NSString* infoPlistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    return [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
}

NSString* appIdForAppPath(NSString* appPath) {
    if(!appPath) return nil;
    return infoDictionaryForAppPath(appPath)[@"CFBundleIdentifier"];
}

void cleanRestrictions(void) {
    NSString* clientTruthPath = @"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/ClientTruth.plist";
    NSURL* clientTruthURL = [NSURL fileURLWithPath:clientTruthPath];
    NSDictionary* clientTruthDictionary = [NSDictionary dictionaryWithContentsOfURL:clientTruthURL];

    if(!clientTruthDictionary) return;

    NSArray* valuesArr;

    NSDictionary* lsdAppRemoval = clientTruthDictionary[@"com.apple.lsd.appremoval"];
    if(lsdAppRemoval && [lsdAppRemoval isKindOfClass:NSDictionary.class]) {
        NSDictionary* clientRestrictions = lsdAppRemoval[@"clientRestrictions"];
        if(clientRestrictions && [clientRestrictions isKindOfClass:NSDictionary.class]) {
            NSDictionary* unionDict = clientRestrictions[@"union"];
            if(unionDict && [unionDict isKindOfClass:NSDictionary.class]) {
                NSDictionary* removedSystemAppBundleIDs = unionDict[@"removedSystemAppBundleIDs"];
                if(removedSystemAppBundleIDs && [removedSystemAppBundleIDs isKindOfClass:NSDictionary.class]) {
                    valuesArr = removedSystemAppBundleIDs[@"values"];
                }
            }
        }
    }

    if(!valuesArr || !valuesArr.count) return;

    NSMutableArray* valuesArrM = valuesArr.mutableCopy;
    __block BOOL changed = NO;

    [valuesArrM enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSString* value, NSUInteger idx, BOOL *stop) {
        if(!isRemovableSystemApp(value))
        {
            [valuesArrM removeObjectAtIndex:idx];
            changed = YES;
        }
    }];

    if(!changed) return;

    NSMutableDictionary* clientTruthDictionaryM = (__bridge_transfer NSMutableDictionary*)CFPropertyListCreateDeepCopy(kCFAllocatorDefault, (__bridge CFDictionaryRef)clientTruthDictionary, kCFPropertyListMutableContainersAndLeaves);
    
    clientTruthDictionaryM[@"com.apple.lsd.appremoval"][@"clientRestrictions"][@"union"][@"removedSystemAppBundleIDs"][@"values"] = valuesArrM;

    [clientTruthDictionaryM writeToURL:clientTruthURL error:nil];

    killall(@"profiled", NO); // profiled needs to restart for the changes to apply
}

NSSet<NSString*>* immutableAppBundleIdentifiers(void) {
    NSMutableSet* systemAppIdentifiers = [NSMutableSet new];

    LSEnumerator* enumerator = [LSEnumerator enumeratorForApplicationProxiesWithOptions:0];
    LSApplicationProxy* appProxy;
    while(appProxy = [enumerator nextObject]) {
        if(appProxy.installed) {
            if(![appProxy.bundleURL.path hasPrefix:@"/private/var/containers"]) {
                [systemAppIdentifiers addObject:appProxy.bundleIdentifier.lowercaseString];
            }
        }
    }

    return systemAppIdentifiers.copy;
}

void applyPatchesToInfoDictionary(NSString* appPath) {
    NSURL* appURL = [NSURL fileURLWithPath:appPath];
    NSURL* infoPlistURL = [appURL URLByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary* infoDictM = [[NSDictionary dictionaryWithContentsOfURL:infoPlistURL error:nil] mutableCopy];
    if(!infoDictM) return;

    // Enable Notifications
    infoDictM[@"SBAppUsesLocalNotifications"] = @1;

    // Remove system claimed URL schemes if existant
    NSSet* appleSchemes = systemURLSchemes();
    NSArray* CFBundleURLTypes = infoDictM[@"CFBundleURLTypes"];
    if([CFBundleURLTypes isKindOfClass:[NSArray class]]) {
        NSMutableArray* CFBundleURLTypesM = [NSMutableArray new];

        for(NSDictionary* URLType in CFBundleURLTypes) {
            if(![URLType isKindOfClass:[NSDictionary class]]) continue;

            NSMutableDictionary* modifiedURLType = URLType.mutableCopy;
            NSArray* URLSchemes = URLType[@"CFBundleURLSchemes"];
            if(URLSchemes) {
                NSMutableSet* URLSchemesSet = [NSMutableSet setWithArray:URLSchemes];
                for(NSString* existingURLScheme in [URLSchemesSet copy]) {
                    if(![existingURLScheme isKindOfClass:[NSString class]]) {
                        [URLSchemesSet removeObject:existingURLScheme];
                        continue;
                    }

                    if([appleSchemes containsObject:existingURLScheme.lowercaseString]) {
                        [URLSchemesSet removeObject:existingURLScheme];
                    }
                }
                modifiedURLType[@"CFBundleURLSchemes"] = [URLSchemesSet allObjects];
            }
            [CFBundleURLTypesM addObject:modifiedURLType.copy];
        }

        infoDictM[@"CFBundleURLTypes"] = CFBundleURLTypesM.copy;
    }

    [infoDictM writeToURL:infoPlistURL error:nil];
}

int signApp(NSString* appPath) {
    NSDictionary* appInfoDict = infoDictionaryForAppPath(appPath);
    if(!appInfoDict) return 172;

    NSString* executablePath = appMainExecutablePathForAppPath(appPath);
    if(!executablePath) return 176;

    if(![[NSFileManager defaultManager] fileExistsAtPath:executablePath]) return 174;
    
    NSObject *kwBundleIsPreSigned = appInfoDict[@"KWBundlePreSigned"];
    if([kwBundleIsPreSigned isKindOfClass:[NSNumber class]]) {
        // if KSBundlePreSigned = YES, this bundle has been externally signed so we can skip over signing it now
        NSNumber *kwBundleIsPreSignedNum = (NSNumber *)kwBundleIsPreSigned;
        if([kwBundleIsPreSignedNum boolValue] == YES) {
            NSLog(@"[signApp] taking fast path for app which declares it has already been signed (%@)", executablePath);
            return 0;
        }
    }

    SecStaticCodeRef codeRef = getStaticCodeRef(executablePath);
    if(codeRef != NULL) {
        if(codeCertChainContainsFakeAppStoreExtensions(codeRef)) {
            NSLog(@"[signApp] taking fast path for app signed using a custom root certificate (%@)", executablePath);
            CFRelease(codeRef);
            return 0;
        }
    } else {
        NSLog(@"[signApp] failed to get static code, can't derive entitlements from %@, continuing anways...", executablePath);
    }

    if(!isLdidInstalled()) return 173;

    NSString* certPath = [mineekStoreAppPath() stringByAppendingPathComponent:@"cert.p12"];
    NSString* certArg = [@"-K" stringByAppendingPathComponent:certPath];
    NSString* passwordArg = @"-Upassword";
    NSString* errorOutput;
    int ldidRet;

    NSDictionary* entitlements = dumpEntitlements(codeRef);
    CFRelease(codeRef);
    
    if(!entitlements) {
        NSLog(@"app main binary has no entitlements");
        ldidRet = runLdid(@[@"-S", certArg, passwordArg, appPath], nil, &errorOutput);
    } else {
        // app has entitlements, keep them
        ldidRet = runLdid(@[@"-s", certArg, passwordArg, appPath], nil, &errorOutput);
    }

    NSLog(@"ldid exited with status %d", ldidRet);

    NSLog(@"- ldid error output start -");

    printMultilineNSString(errorOutput);

    NSLog(@"- ldid error output end -");

    if(ldidRet == 0) {
        return 0;
    } else {
        return 175;
    }
}

NSURL* findAppURLInBundleURL(NSURL* bundleURL) {
    NSString* appName = findAppNameInBundlePath(bundleURL.path);
    if(!appName) return nil;
    return [bundleURL URLByAppendingPathComponent:appName];
}

void fixPermissionsOfAppBundle(NSString* appBundlePath) {
    // Apply correct permissions (First run, set everything to 644, owner 33)
    NSURL* fileURL;
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:appBundlePath] includingPropertiesForKeys:nil options:0 errorHandler:nil];
    while(fileURL = [enumerator nextObject]) {
        NSString* filePath = fileURL.path;
        chown(filePath.fileSystemRepresentation, 33, 33);
        chmod(filePath.fileSystemRepresentation, 0644);
    }

    // Apply correct permissions (Second run, set executables and directories to 0755)
    enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:appBundlePath] includingPropertiesForKeys:nil options:0 errorHandler:nil];
    while(fileURL = [enumerator nextObject]) {
        NSString* filePath = fileURL.path;

        BOOL isDir;
        [[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&isDir];

        if(isDir || isMachoFile(filePath)) {
            chmod(filePath.fileSystemRepresentation, 0755);
        }
    }
}

BOOL codeCertChainContainsFakeAppStoreExtensions(SecStaticCodeRef codeRef) {
    if(codeRef == NULL) {
        NSLog(@"[codeCertChainContainsFakeAppStoreExtensions] attempted to check cert chain of null static code object");
        return NO;
    }
    
    CFDictionaryRef signingInfo = NULL;
    OSStatus result;
  
    result = SecCodeCopySigningInformation(codeRef, kSecCSSigningInformation, &signingInfo);

    if(result != errSecSuccess) {
        NSLog(@"[codeCertChainContainsFakeAppStoreExtensions] failed to copy signing info from static code");
        return NO;
    }
    
    CFArrayRef certificates = CFDictionaryGetValue(signingInfo, kSecCodeInfoCertificates);
    if(certificates == NULL || CFArrayGetCount(certificates) == 0) {
        return NO;
    }

    // If we match the standard Apple policy, we are signed properly, but we haven't been deliberately signed with a custom root
    
    SecPolicyRef appleAppStorePolicy = SecPolicyCreateWithProperties(kSecPolicyAppleiPhoneApplicationSigning, NULL);

    SecTrustRef trust = NULL;
    SecTrustCreateWithCertificates(certificates, appleAppStorePolicy, &trust);

    if(SecTrustEvaluateWithError(trust, nil)) {
        CFRelease(trust);
        CFRelease(appleAppStorePolicy);
        CFRelease(signingInfo);
        
        NSLog(@"[codeCertChainContainsFakeAppStoreExtensions] found certificate extension, but was issued by Apple (App Store)");
        return NO;
    }

    // We haven't matched Apple, so keep going. Is the app profile signed?
        
    CFRelease(appleAppStorePolicy);
    
    SecPolicyRef appleProfileSignedPolicy = SecPolicyCreateWithProperties(kSecPolicyAppleiPhoneProfileApplicationSigning, NULL);
    if(SecTrustSetPolicies(trust, appleProfileSignedPolicy) != errSecSuccess) {
        NSLog(@"[codeCertChainContainsFakeAppStoreExtensions] error replacing trust policy to check for profile-signed app");
        CFRelease(trust);
        CFRelease(signingInfo);
        return NO;
    }
        
    if(SecTrustEvaluateWithError(trust, nil)) {
        CFRelease(trust);
        CFRelease(appleProfileSignedPolicy);
        CFRelease(signingInfo);
        
        NSLog(@"[codeCertChainContainsFakeAppStoreExtensions] found certificate extension, but was issued by Apple (profile-signed)");
        return NO;
    }
    
    // Still haven't matched Apple. Are we using a custom root that would take the App Store fastpath?
    CFRelease(appleProfileSignedPolicy);
    
    // Cert chain should be of length 3
    if(CFArrayGetCount(certificates) != 3) {
        CFRelease(signingInfo);
        
        NSLog(@"[codeCertChainContainsFakeAppStoreExtensions] certificate chain length != 3");
        return NO;
    }
        
    // AppleCodeSigning only checks for the codeSigning EKU by default
    SecPolicyRef customRootPolicy = SecPolicyCreateWithProperties(kSecPolicyAppleCodeSigning, NULL);
    SecPolicySetOptionsValue(customRootPolicy, CFSTR("LeafMarkerOid"), CFSTR("1.2.840.113635.100.6.1.3"));
    
    if(SecTrustSetPolicies(trust, customRootPolicy) != errSecSuccess) {
        NSLog(@"[codeCertChainContainsFakeAppStoreExtensions] error replacing trust policy to check for custom root");
        CFRelease(trust);
        CFRelease(signingInfo);
        return NO;
    }

    // Need to add our certificate chain to the anchor as it is expected to be a self-signed root
    SecTrustSetAnchorCertificates(trust, certificates);
    
    BOOL evaluatesToCustomAnchor = SecTrustEvaluateWithError(trust, nil);
    NSLog(@"[codeCertChainContainsFakeAppStoreExtensions] app signed with non-Apple certificate %@ using valid custom certificates", evaluatesToCustomAnchor ? @"IS" : @"is NOT");
    
    CFRelease(trust);
    CFRelease(customRootPolicy);
    CFRelease(signingInfo);
    
    return evaluatesToCustomAnchor;
}

NSSet<NSString*>* systemURLSchemes(void) {
    LSEnumerator* enumerator = [LSEnumerator enumeratorForApplicationProxiesWithOptions:0];

    NSMutableSet* systemURLSchemesSet = [NSMutableSet new];
    LSApplicationProxy* proxy;
    while(proxy = [enumerator nextObject]) {
        if(isRemovableSystemApp(proxy.bundleIdentifier) || ![proxy.bundleURL.path hasPrefix:@"/private/var/containers"]) {
            for(NSString* claimedURLScheme in proxy.claimedURLSchemes) {
                if([claimedURLScheme isKindOfClass:NSString.class]) {
                    [systemURLSchemesSet addObject:claimedURLScheme.lowercaseString];
                }
            }
        }
    }

    return systemURLSchemesSet.copy;
}

NSString* appMainExecutablePathForAppPath(NSString* appPath) {
    if(!appPath) return nil;
    return [appPath stringByAppendingPathComponent:infoDictionaryForAppPath(appPath)[@"CFBundleExecutable"]];
}

void installLdid(NSString* ldidToCopyPath, NSString* ldidVersion) {
    if(![[NSFileManager defaultManager] fileExistsAtPath:ldidToCopyPath]) return;

    NSString* ldidPath = [mineekStoreAppPath() stringByAppendingPathComponent:@"ldid"];
    NSString* ldidVersionPath = [mineekStoreAppPath() stringByAppendingPathComponent:@"ldid.version"];

    if([[NSFileManager defaultManager] fileExistsAtPath:ldidPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:ldidPath error:nil];
    }

    [[NSFileManager defaultManager] copyItemAtPath:ldidToCopyPath toPath:ldidPath error:nil];

    NSData* ldidVersionData = [ldidVersion dataUsingEncoding:NSUTF8StringEncoding];
    [ldidVersionData writeToFile:ldidVersionPath atomically:YES];

    chmod(ldidPath.fileSystemRepresentation, 0755);
    chmod(ldidVersionPath.fileSystemRepresentation, 0644);
}

BOOL isLdidInstalled(void) {
    NSString* ldidPath = [mineekStoreAppPath() stringByAppendingPathComponent:@"ldid"];
    return [[NSFileManager defaultManager] fileExistsAtPath:ldidPath];
}

int runLdid(NSArray* args, NSString** output, NSString** errorOutput) {
    NSString* ldidPath = [mineekStoreAppPath() stringByAppendingPathComponent:@"ldid"];
    NSMutableArray* argsM = args.mutableCopy ?: [NSMutableArray new];
    [argsM insertObject:ldidPath.lastPathComponent atIndex:0];

    NSUInteger argCount = [argsM count];
    char **argsC = (char **)malloc((argCount + 1) * sizeof(char*));

    for (NSUInteger i = 0; i < argCount; i++) {
        argsC[i] = strdup([[argsM objectAtIndex:i] UTF8String]);
    }
    argsC[argCount] = NULL;

    posix_spawn_file_actions_t action;
    posix_spawn_file_actions_init(&action);

    int outErr[2];
    pipe(outErr);
    posix_spawn_file_actions_adddup2(&action, outErr[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&action, outErr[0]);

    int out[2];
    pipe(out);
    posix_spawn_file_actions_adddup2(&action, out[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&action, out[0]);
    
    pid_t task_pid;
    int status = -200;
    int spawnError = posix_spawn(&task_pid, [ldidPath fileSystemRepresentation], &action, NULL, (char* const*)argsC, NULL);
    for (NSUInteger i = 0; i < argCount; i++) {
        free(argsC[i]);
    }
    free(argsC);

    if(spawnError != 0) {
        NSLog(@"posix_spawn error %d\n", spawnError);
        return spawnError;
    }

    do {
        if (waitpid(task_pid, &status, 0) != -1) {
            //printf("Child status %dn", WEXITSTATUS(status));
        } else {
            perror("waitpid");
            return -222;
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));

    close(outErr[1]);
    close(out[1]);

    NSString* ldidOutput = getNSStringFromFile(out[0]);
    if(output) {
        *output = ldidOutput;
    }

    NSString* ldidErrorOutput = getNSStringFromFile(outErr[0]);
    if(errorOutput) {
        *errorOutput = ldidErrorOutput;
    }

    return WEXITSTATUS(status);
}

BOOL isMachoFile(NSString* filePath) {
    FILE* file = fopen(filePath.fileSystemRepresentation, "r");
    if(!file) return NO;

    fseek(file, 0, SEEK_SET);
    uint32_t magic;
    fread(&magic, sizeof(uint32_t), 1, file);
    fclose(file);

    return magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64;
}

void refreshAppRegistrations(BOOL system) {
	registerPath(mineekStoreAppPath(), NO, system);

	for(NSString* appPath in mineekStoreInstalledAppBundlePaths()) {
		registerPath(appPath, NO, system);
	}
}

int main(int argc, char *argv[], char *envp[]) {
	@autoreleasepool {
		if(argc <= 1) return -1;

		if(getuid() != 0) {
			NSLog(@"ERROR: mineekStoreHelper has to be run as root.");
			return -1;
		}

		NSMutableArray* args = [NSMutableArray new];
		for (int i = 1; i < argc; i++) {
			[args addObject:[NSString stringWithUTF8String:argv[i]]];
		}

		NSLog(@"MineekStoreHelper invoked with arguments: %@", args);

		int ret = 0;
		NSString* cmd = args.firstObject;

        if([cmd isEqualToString:@"install"]) {
			if(args.count < 2) return -3;
			NSString* ipaPath = args.lastObject;
			ret = installIpa(ipaPath);
		} else if([cmd isEqualToString:@"install-ldid"]) {
			if(args.count < 3) return -3;
			NSString* ldidPath = args[1];
			NSString* ldidVersion = args[2];
			installLdid(ldidPath, ldidVersion);
		} else if([cmd isEqualToString:@"refresh"]) {
			refreshAppRegistrations(YES);
		} else if([cmd isEqualToString:@"refresh-all"]) {
			cleanRestrictions();
			[[NSFileManager defaultManager] removeItemAtPath:@"/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache/Library/Caches/com.apple.IconsCache" error:nil];
			[[LSApplicationWorkspace defaultWorkspace] _LSPrivateRebuildApplicationDatabasesForSystemApps:YES internal:YES user:YES];
			refreshAppRegistrations(YES);
			killall(@"backboardd", YES);
		} else if([cmd isEqualToString:@"respring"]) {
			killall(@"backboardd", YES);
        }

        NSLog(@"trollstorehelper returning %d", ret);
		return ret;
    }
}
