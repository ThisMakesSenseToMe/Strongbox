//
//  DebugHelper.m
//  Strongbox-iOS
//
//  Created by Mark on 01/10/2019.
//  Copyright © 2014-2021 Mark McGuill. All rights reserved.
//

#import "DebugHelper.h"
#import "Utils.h"
#import "FileManager.h"
#import <mach-o/arch.h>
#import "NSDate+Extensions.h"
#import "NSArray+Extensions.h"
#import "SafeStorageProviderFactory.h"
#import "WorkingCopyManager.h"
#import "ProUpgradeIAPManager.h"
#import "Strongbox-Swift.h"

#if TARGET_OS_IPHONE

#import "DatabasePreferences.h"
#import "AppPreferences.h"
#import "git-version.h"
#import "SyncManager.h"
#import "CustomizationManager.h"


#else

#import <objc/message.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#import "Settings.h"
#import "MacSyncManager.h"
#import "FileManager.h"
#import "MacDatabasePreferences.h"


#endif

@implementation DebugHelper

+ (NSString*)getAboutDebugString {
    NSArray* lines = [self getDebugLines];
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSString*)getCrashEmailDebugString {
    NSArray* lines = [self getDebugLines];
    return [lines componentsJoinedByString:@"\n"];
}

#if !TARGET_OS_IPHONE

static NSString *ModelIdentifier()
{
    NSString *result=@"Unknown Mac";
    size_t len=0;
    sysctlbyname("hw.model", NULL, &len, NULL, 0);
    if (len) {
        NSMutableData *data=[NSMutableData dataWithLength:len];
        sysctlbyname("hw.model", [data mutableBytes], &len, NULL, 0);
        result=[NSString stringWithUTF8String:[data bytes]];
    }
    return result;
}

#define OPProcessValueUnknown UINT_MAX



int OPParentIDForProcessID(int pid)
{
    struct kinfo_proc info;
    size_t length = sizeof(struct kinfo_proc);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
        return OPProcessValueUnknown;
    if (length == 0)
        return OPProcessValueUnknown;
    return info.kp_eproc.e_ppid;
}

+ (NSString *)systemVersion {
    static NSString *systemVersion = nil;

    if (!systemVersion) {
        if ( [NSProcessInfo.processInfo respondsToSelector:@selector(operatingSystemVersionString)] ) {
            systemVersion = NSProcessInfo.processInfo.operatingSystemVersionString;
        }
        else {
            systemVersion = @"<Unknown>";
        }
    }

    return systemVersion;
}

#endif

+ (NSString*)getProStatusDisplayString {
    BOOL isAProBundle;
    BOOL isPro;
    
#if !TARGET_OS_IPHONE
    isAProBundle =  MacCustomizationManager.isAProBundle;
    isPro =Settings.sharedInstance.isPro;
#else
    isAProBundle =  CustomizationManager.isAProBundle;
    isPro = AppPreferences.sharedInstance.isPro;
#endif
    
    NSString* proStatus;
    if ( isAProBundle ) {
        proStatus = @"Lifetime Pro (App SKU is Pro)";
    }
    else {
        if ( isPro ) {
            if ( ProUpgradeIAPManager.sharedInstance.isLegacyLifetimeIAPPro ) { 
                proStatus = @"Lifetime Pro (via In-App Purchase)";
            }
            else if ( ProUpgradeIAPManager.sharedInstance.hasActiveYearlySubscription ){
                proStatus = @"Pro (Yearly subscription)";
            }
            else if ( ProUpgradeIAPManager.sharedInstance.hasActiveMonthlySubscription ) {
                proStatus = @"Pro (Monthly subscription)";
            }
            else {
                proStatus = @"Pro (Unknown Entitlement)"; 
            }
        }
        else {
            proStatus = @"Not Pro (No Entitlement)";
        }
    }
    
    return proStatus;
}

+ (NSArray<NSString*>*)getDebugLines {
    NSMutableArray<NSString*>* debugLines = [NSMutableArray array];
    
#if TARGET_OS_IPHONE
    NSString* model = [[UIDevice currentDevice] model];
    NSString* systemName = [[UIDevice currentDevice] systemName];
    NSString* systemVersion = [[UIDevice currentDevice] systemVersion];
#else
    NSString* model = ModelIdentifier();
    NSString* systemName = @"MacOS";
    NSString* systemVersion = [DebugHelper systemVersion];
#endif
    
    
    
    NSString* proStatus = [DebugHelper getProStatusDisplayString];
    
#if TARGET_OS_IPHONE
    NSString* pro = [[AppPreferences sharedInstance] isPro] ? @"P" : @"";
    [debugLines addObject:@"-------------------- App Summary -----------------------"];
    
    [debugLines addObject:[NSString stringWithFormat:@"App SKU: %@%@", StrongboxProductBundle.displayName, StrongboxProductBundle.isTestFlightBuild ? @" (TestFlight)" : @""]];
    [debugLines addObject:[NSString stringWithFormat:@"Pro Status: %@", proStatus]];
    [debugLines addObject:[NSString stringWithFormat:@"Platform: %@ %@", systemName, systemVersion]];
        
    [debugLines addObject:@"\n-------------------- Databases Summary -----------------------"];
    
    int i = 0;
    for(DatabasePreferences *safe in DatabasePreferences.allDatabases) {
        NSString* spName = [SafeStorageProviderFactory getStorageDisplayName:safe];
        
        NSDate* mod;
        unsigned long long fileSize;
        NSURL* url = [WorkingCopyManager.sharedInstance getLocalWorkingCache:safe.uuid modified:&mod fileSize:&fileSize];
        
        NSString* syncState;
        if (url) {
            syncState = [NSString stringWithFormat:@"%@ (%@ Sync) => %@ (%@)", safe.nickName, spName, mod.friendlyDateTimeStringBothPrecise, friendlyFileSizeString(fileSize)];
        }
        else {
            syncState = [NSString stringWithFormat:@"%@ (%@ Sync) => Unknown", safe.nickName, spName];
        }
        
        [debugLines addObject:[NSString stringWithFormat:@"%d. %@", ++i, syncState]];
    }
    
    [debugLines addObject:@"--------------------------------------------------------------\n"];
    [debugLines addObject:[NSString stringWithFormat:@"Strongbox %@ Debug Information at %@", [Utils getAppVersion], NSDate.date.friendlyDateTimeStringBothPrecise]];
    [debugLines addObject:@"--------------------"];
    
    
    [debugLines addObject:[NSString stringWithFormat:@"Version Info: %@ [%@ (%@)@%@-%@]", [Utils getAppBundleId], [Utils getAppVersion], [Utils getAppBuildNumber], GIT_SHA_VERSION, pro]];
    [debugLines addObject:[NSString stringWithFormat:@"NECF: %ld", AppPreferences.sharedInstance.numberOfEntitlementCheckFails]];
    [debugLines addObject:[NSString stringWithFormat:@"LEC: %@", AppPreferences.sharedInstance.lastEntitlementCheckAttempt.friendlyDateTimeStringBothPrecise]];
#else
    
    
    
    
    NSString* pro = Settings.sharedInstance.isPro ? @"P" : @"";
    [debugLines addObject:@"-------------------- App Summary -----------------------"];
    
    [debugLines addObject:[NSString stringWithFormat:@"App SKU: %@%@", StrongboxProductBundle.displayName, StrongboxProductBundle.isTestFlightBuild ? @" (TestFlight)" : @""]];
    [debugLines addObject:[NSString stringWithFormat:@"Pro Status: %@", proStatus]];
    [debugLines addObject:[NSString stringWithFormat:@"Platform: %@ %@", systemName, systemVersion]];
    [debugLines addObject:@"\n-------------------- Databases Summary -----------------------"];
    
    
    
    
    int i = 0;
    for(MacDatabasePreferences *safe in MacDatabasePreferences.allDatabases ) {
        NSString* spName = [SafeStorageProviderFactory getStorageDisplayName:safe];
        NSDate* mod;
        unsigned long long fileSize;
        NSURL* url = [WorkingCopyManager.sharedInstance getLocalWorkingCache:safe.uuid modified:&mod fileSize:&fileSize];
        
        NSString* syncState;
        if (url) {
            syncState = [NSString stringWithFormat:@"%@ (%@ Sync) => %@ (%@)", safe.nickName, spName, mod.friendlyDateTimeStringBothPrecise, friendlyFileSizeString(fileSize)];
        }
        else {
            syncState = [NSString stringWithFormat:@"%@ (%@ Sync) => Unknown", safe.nickName, spName];
        }
        
        [debugLines addObject:[NSString stringWithFormat:@"%d. %@", ++i, syncState]];
    }

    [debugLines addObject:@"--------------------------------------------------------------\n"];
    [debugLines addObject:[NSString stringWithFormat:@"Strongbox %@ Debug Information at %@", [Utils getAppVersion], NSDate.date.friendlyDateTimeStringBothPrecise]];
    [debugLines addObject:@"--------------------"];
    AppDelegate* appDelegate = NSApplication.sharedApplication.delegate;
    [debugLines addObject:[NSString stringWithFormat:@"Launched as Login Item: %@", localizedYesOrNoFromBool(appDelegate.isWasLaunchedAsLoginItem)]];

    [debugLines addObject:[NSString stringWithFormat:@"App Version: %@ [%@ (%@)-%@]", [Utils getAppBundleId], [Utils getAppVersion], [Utils getAppBuildNumber], pro]];
    [debugLines addObject:[NSString stringWithFormat:@"NECF: %ld", Settings.sharedInstance.numberOfEntitlementCheckFails]];
    [debugLines addObject:[NSString stringWithFormat:@"LEC: %@", Settings.sharedInstance.lastEntitlementCheckAttempt.friendlyDateTimeStringBothPrecise]];
#endif

    [debugLines addObject:[NSString stringWithFormat:@"LLIAPP: %hhd", ProUpgradeIAPManager.sharedInstance.isLegacyLifetimeIAPPro]];
    [debugLines addObject:[NSString stringWithFormat:@"AMS: %hhd", ProUpgradeIAPManager.sharedInstance.hasActiveMonthlySubscription]];
    [debugLines addObject:[NSString stringWithFormat:@"AYS: %hhd", ProUpgradeIAPManager.sharedInstance.hasActiveYearlySubscription]];
    [debugLines addObject:[NSString stringWithFormat:@"FTA: %hhd", ProUpgradeIAPManager.sharedInstance.isFreeTrialAvailable]];
        
    

    [debugLines addObject:@"--------------------"];
    [debugLines addObject:@"Device"];
    [debugLines addObject:@"--------------------"];

    const NXArchInfo *info = NXGetLocalArchInfo();
    NSString *typeOfCpu = info ? [NSString stringWithUTF8String:info->description] : @"Unknown";

    [debugLines addObject:[NSString stringWithFormat:@"Model: %@", model]];
    [debugLines addObject:[NSString stringWithFormat:@"CPU: %@", typeOfCpu]];
    [debugLines addObject:[NSString stringWithFormat:@"System Name: %@", systemName]];
    [debugLines addObject:[NSString stringWithFormat:@"System Version: %@", systemVersion]];

    

    [debugLines addObject:@"--------------------"];
    [debugLines addObject:@"Preferences"];
    [debugLines addObject:@"--------------------"];

#if TARGET_OS_IPHONE
    NSUserDefaults *defs = AppPreferences.sharedInstance.sharedAppGroupDefaults;
    NSDictionary* prefs = [defs persistentDomainForName:AppPreferences.sharedInstance.appGroupName];
#else
    NSUserDefaults *defs = Settings.sharedInstance.sharedAppGroupDefaults;
    NSDictionary* prefs = [defs persistentDomainForName:Settings.sharedInstance.appGroupName];
#endif
    
    for (NSString* pref in prefs) {
        if ( ![pref hasPrefix:@"com.apple"] &&
            ![pref hasPrefix:@"Apple"] &&
            ![pref hasPrefix:@"appLockPin"] &&
            ![pref hasPrefix:@"NS"] &&
            ![pref hasPrefix:@"searchFieldRecents"] &&
            ![pref hasPrefix:@"passwordGenerationConfig"] &&
            ![pref hasPrefix:@"passwordGenerationSettings"] &&
            ![pref hasPrefix:@"autoFillNewRecordSettings"] ) {
            [debugLines addObject:[NSString stringWithFormat:@"%@: %@", pref, [defs valueForKey:pref]]];
        }
    }

#if TARGET_OS_IPHONE
    long epoch = (long)AppPreferences.sharedInstance.installDate.timeIntervalSince1970;
    [debugLines addObject:[NSString stringWithFormat:@"Ep: %ld", epoch]];
    [debugLines addObject:[NSString stringWithFormat:@"Flags: %@%@", pro, [AppPreferences.sharedInstance getFlagsStringForDiagnostics]]];

    
    

    [debugLines addObject:@"--------------------"];
    [debugLines addObject:@"Last Crash"];
    [debugLines addObject:@"--------------------"];

    if ([NSFileManager.defaultManager fileExistsAtPath:FileManager.sharedInstance.archivedCrashFile.path]) {
        NSData* crashFileData = [NSData dataWithContentsOfURL:FileManager.sharedInstance.archivedCrashFile];
        NSString* jsonCrash = [[NSString alloc] initWithData:crashFileData encoding:NSUTF8StringEncoding];
        [debugLines addObject:[NSString stringWithFormat:@"JSON Crash:%@", jsonCrash]];
    }
#endif
    
    [debugLines addObject:@"--------------------"];
    [debugLines addObject:@"Sync"];
    [debugLines addObject:@"--------------------"];

#if TARGET_OS_IPHONE
    for(DatabasePreferences *safe in DatabasePreferences.allDatabases) {
        SyncStatus *syncStatus = [SyncManager.sharedInstance getSyncStatus:safe];
#else
    for(MacDatabasePreferences *safe in MacDatabasePreferences.allDatabases ) {
        SyncStatus *syncStatus = [MacSyncManager.sharedInstance getSyncStatus:safe];
#endif
        NSMutableArray<NSArray*>* mutableSyncs = NSMutableArray.array;
        NSMutableSet<NSUUID*>* set = NSMutableSet.set;
        NSMutableArray *currentSync;
        for (SyncStatusLogEntry* entry in syncStatus.changeLog) {
            if (![set containsObject:entry.syncId]) {
                currentSync = NSMutableArray.array;
                [mutableSyncs addObject:currentSync];
                [set addObject:entry.syncId];
            }
            
            [currentSync addObject:entry];
        }
        
        NSArray<NSArray<SyncStatusLogEntry*>*> *syncs = [[mutableSyncs reverseObjectEnumerator] allObjects];
        
        
        
        NSArray* failedSyncs = [syncs filter:^BOOL(NSArray<SyncStatusLogEntry *> * _Nonnull sync) {
            return [sync anyMatch:^BOOL(SyncStatusLogEntry * _Nonnull status) {
                return status.state == kSyncOperationStateError;
            }];
        }];
        

        NSString* spName = [SafeStorageProviderFactory getStorageDisplayName:safe];
        
        for (NSArray* failed in failedSyncs) {
            [debugLines addObject:[NSString stringWithFormat:@"============== [%@] Failed Sync to [%@] ===============", safe.nickName, spName]];
            [debugLines addObjectsFromArray:failed];
            [debugLines addObject:@"=========================================="];
        }
        
        
        
        NSDate* mod;
        unsigned long long fileSize;
        NSURL* url = [WorkingCopyManager.sharedInstance getLocalWorkingCache:safe.uuid modified:&mod fileSize:&fileSize];
        
        NSString* syncState;
        if (url) {
            syncState = [NSString stringWithFormat:@"%@ (%@ Sync) => %@ (%@)", safe.nickName, spName, mod.friendlyDateTimeStringBothPrecise, friendlyFileSizeString(fileSize)];
        }
        else {
            syncState = [NSString stringWithFormat:@"%@ (%@ Sync) => Unknown", safe.nickName, spName];
        }
        
        [debugLines addObject:syncState];
    }

    [debugLines addObject:@"--------------------"];

    

#if TARGET_OS_IPHONE
    [debugLines addObjectsFromArray:[DebugHelper listDirectoryRecursive:FileManager.sharedInstance.appSupportDirectory]];
    [debugLines addObjectsFromArray:[DebugHelper listDirectoryRecursive:FileManager.sharedInstance.documentsDirectory]];


#endif
        
    [debugLines addObjectsFromArray:[DebugHelper listDirectoryRecursive:FileManager.sharedInstance.sharedAppGroupDirectory]];

    

    [debugLines addObject:@"--------------------"];

        
#if TARGET_OS_IPHONE
    for(DatabasePreferences *safe in DatabasePreferences.allDatabases) {
        NSString* spName = [SafeStorageProviderFactory getStorageDisplayName:safe];
        [debugLines addObject:@"================================================================="];
        [debugLines addObject:[NSString stringWithFormat:@"[%@] on [%@] Config", safe.nickName, spName]];
        [debugLines addObject:@"================================================================="];

        NSMutableDictionary* jsonDict = [safe getJsonSerializationDictionary].mutableCopy;
        jsonDict[@"keyFileBookmark"] = jsonDict[@"keyFileBookmark"] ? @"<redacted>" : @"<Not Set>";
        jsonDict[@"keyFileFileName"] = jsonDict[@"keyFileFileName"] ? @"<redacted>" : @"<Not Set>";
        NSString *thisSafe = [jsonDict description];
        [debugLines addObject:thisSafe];
    }
#else
    for(MacDatabasePreferences *safe in MacDatabasePreferences.allDatabases ) {
        NSString* spName = [SafeStorageProviderFactory getStorageDisplayName:safe];
        [debugLines addObject:@"================================================================="];
        [debugLines addObject:[NSString stringWithFormat:@"[%@] on [%@] Config", safe.nickName, spName]];
        [debugLines addObject:@"================================================================="];

        NSMutableDictionary<NSString*, NSString*>* mut = safe.debugInfoLines.mutableCopy;
        
        [mut removeObjectForKey:@"_storageInfo"]; 
        
        for ( NSString* key in mut.allKeys ) {
            NSString* val = mut[key];
            [debugLines addObject:[NSString stringWithFormat:@"%@ = %@", key, val]];
        }
        
        [debugLines addObject:@"================================================================="];
    }
#endif

    [debugLines addObject:@"--------------------"];
    
    return debugLines;
}

+ (NSArray<NSString*>*)listDirectoryRecursive:(NSURL*)URL {
    return [DebugHelper listDirectoryRecursive:URL listRelativeToURL:URL];
}

+ (NSArray<NSString*>*)listDirectoryRecursive:(NSURL*)URL listRelativeToURL:(NSURL*)listRelativeToURL {
    NSMutableArray<NSString*>* ret = [NSMutableArray array];
        
    NSArray<NSURL*>* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:URL
                                                              includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                                               options:kNilOptions
                                                                                                 error:NULL];
    
    for (NSURL *file in contents) {
        NSString* relativePath = file.path.length > listRelativeToURL.path.length ? [file.path substringFromIndex:listRelativeToURL.path.length + 1] : file.path;

        NSError *error;
        NSNumber *isDirectory = nil;

        if (![file getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error]) {
            [ret addObject:[NSString stringWithFormat:@"Error %@", file]];
        }
        else {
            if (![isDirectory boolValue]) {
                NSDictionary* attributes = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:&error];
                
                if (error) {
                    [ret addObject:[NSString stringWithFormat:@"%@ - %@", relativePath, error]];
                }
                else {
                    [ret addObject:[NSString stringWithFormat:@"[%@] %@ - %@", relativePath, friendlyFileSizeString(attributes.fileSize), attributes.fileModificationDate.friendlyDateTimeStringPrecise]];
                }
            }
            else{

                NSArray* subdir = [self listDirectoryRecursive:file listRelativeToURL:listRelativeToURL];
                [ret addObjectsFromArray:subdir];
            }
        }
    }
    
    return ret;
}

@end
