@import Foundation;
#include <utils.h>

#ifndef main_h
#define main_h

void cleanRestrictions(void);
extern int installApp(NSString* appPackagePath, BOOL sign);
extern int installIpa(NSString* ipaPath);
extern NSString* findAppPathInBundlePath(NSString* bundlePath);
extern NSString* appPathForAppId(NSString* appId);
extern NSString* findAppNameInBundlePath(NSString* bundlePath);
extern NSDictionary* infoDictionaryForAppPath(NSString* appPath);
extern NSString* appIdForAppPath(NSString* appPath);
extern NSSet<NSString*>* immutableAppBundleIdentifiers(void);
extern void applyPatchesToInfoDictionary(NSString* appPath);
extern int signApp(NSString* appPath);
extern NSURL* findAppURLInBundleURL(NSURL* bundleURL);
extern void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleID, int reasonID, bool report, NSString *description);
extern void fixPermissionsOfAppBundle(NSString* appBundlePath);
extern NSSet<NSString*>* systemURLSchemes(void);
extern NSString* appMainExecutablePathForAppPath(NSString* appPath);
extern BOOL codeCertChainContainsFakeAppStoreExtensions(SecStaticCodeRef codeRef);
extern BOOL isMachoFile(NSString* filePath);
extern void refreshAppRegistrations(BOOL system);

extern void installLdid(NSString* ldidToCopyPath, NSString* ldidVersion);
extern BOOL isLdidInstalled(void);
extern int runLdid(NSArray* args, NSString** output, NSString** errorOutput);

#define kCFPreferencesNoContainer CFSTR("kCFPreferencesNoContainer")

#endif /* main_h */
