@import Foundation;
#include "CoreServices.h"

#ifndef utils_h
#define utils_h

typedef struct __SecCode const *SecStaticCodeRef;
typedef CF_OPTIONS(uint32_t, SecCSFlags) {
    kSecCSDefaultFlags = 0
};
#define kSecCSRequirementInformation 1 << 2
#define kSecCSSigningInformation 1 << 1

extern BOOL isRemovableSystemApp(NSString* appId);
extern void killall(NSString* processName, BOOL softly);
extern void printMultilineNSString(NSString* stringToPrint);
extern NSString* getNSStringFromFile(int fd);
extern int fd_is_valid(int fd);
extern void enumerateProcessesUsingBlock(void (^enumerator)(pid_t pid, NSString* executablePath, BOOL* stop));

extern NSArray* mineekStoreInstalledAppBundlePaths(void);
extern NSArray* mineekStoreInstalledAppContainerPaths(void);
extern NSString* mineekStorePath(void);
extern NSString* mineekStoreAppPath(void);

extern SecStaticCodeRef getStaticCodeRef(NSString *binaryPath);
OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, SecCSFlags flags, CFDictionaryRef attributes, SecStaticCodeRef *staticCode);
OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef *information);
CFDataRef SecCertificateCopyExtensionValue(SecCertificateRef certificate, CFTypeRef extensionOID, bool *isCritical);
void SecPolicySetOptionsValue(SecPolicyRef policy, CFStringRef key, CFTypeRef value);
extern NSDictionary* dumpEntitlements(SecStaticCodeRef codeRef);
extern NSDictionary* dumpEntitlementsFromBinaryAtPath(NSString *binaryPath);
extern NSDictionary* dumpEntitlementsFromBinaryData(NSData* binaryData);
extern CFStringRef kSecCodeInfoEntitlementsDict;
extern CFStringRef kSecCodeInfoCertificates;
extern CFStringRef kSecPolicyAppleiPhoneApplicationSigning;
extern CFStringRef kSecPolicyAppleiPhoneProfileApplicationSigning;
extern CFStringRef kSecPolicyLeafMarkerOid;

#endif /* utils_h */
