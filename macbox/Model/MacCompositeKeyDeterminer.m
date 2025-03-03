//
//  MacCompositeKeyDeterminer.m
//  MacBox
//
//  Created by Strongbox on 31/10/2021.
//  Copyright © 2021 Mark McGuill. All rights reserved.
//

#import "MacCompositeKeyDeterminer.h"
#import "Settings.h"
#import "BiometricIdHelper.h"
#import "ManualCredentialsEntry.h"
#import "MacHardwareKeyManager.h"
#import "Utils.h"
#import "WorkingCopyManager.h"
#import "Serializator.h"
#import "KeyFileParser.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import "StrongboxErrorCodes.h"
#import "AutoFillLoadingVC.h"
#import "AppDelegate.h"

@interface MacCompositeKeyDeterminer ()

@property (nonnull) METADATA_PTR database;
@property BOOL isNativeAutoFillAppExtensionOpen;
@property BOOL isAutoFillQuickTypeOpen;
@property (readonly, nullable) NSString* contextAwareKeyFileBookmark;

@property (nonnull, readonly) NSViewController* viewController;
@property MacCompositeKeyDeterminerOnDemandUIProviderBlock onDemandUiProvider;

@end

@implementation MacCompositeKeyDeterminer

+ (instancetype)determinerWithViewController:(NSViewController*)viewController
                                    database:(METADATA_PTR)database
            isNativeAutoFillAppExtensionOpen:(BOOL)isNativeAutoFillAppExtensionOpen {
    return [MacCompositeKeyDeterminer determinerWithViewController:viewController
                                                          database:database
                                  isNativeAutoFillAppExtensionOpen:isNativeAutoFillAppExtensionOpen
                                           isAutoFillQuickTypeOpen:NO];
}

+ (instancetype)determinerWithViewController:(NSViewController*)viewController
                                    database:(METADATA_PTR)database
            isNativeAutoFillAppExtensionOpen:(BOOL)isNativeAutoFillAppExtensionOpen
                     isAutoFillQuickTypeOpen:(BOOL)isAutoFillQuickTypeOpen {

    return [MacCompositeKeyDeterminer determinerWithDatabase:database
                            isNativeAutoFillAppExtensionOpen:isNativeAutoFillAppExtensionOpen
                                     isAutoFillQuickTypeOpen:isAutoFillQuickTypeOpen
                                          onDemandUiProvider:^NSViewController * _Nonnull{
        return viewController;
    }];
}

+ (instancetype)determinerWithDatabase:(METADATA_PTR)database
      isNativeAutoFillAppExtensionOpen:(BOOL)isNativeAutoFillAppExtensionOpen
               isAutoFillQuickTypeOpen:(BOOL)isAutoFillQuickTypeOpen onDemandUiProvider:(MacCompositeKeyDeterminerOnDemandUIProviderBlock)onDemandUiProvider {
    return [[MacCompositeKeyDeterminer alloc] initWithViewController:database
                                    isNativeAutoFillAppExtensionOpen:isNativeAutoFillAppExtensionOpen
                                             isAutoFillQuickTypeOpen:isAutoFillQuickTypeOpen
                                                  onDemandUiProvider:onDemandUiProvider];
}

- (instancetype)initWithViewController:(METADATA_PTR)database
      isNativeAutoFillAppExtensionOpen:(BOOL)isNativeAutoFillAppExtensionOpen
               isAutoFillQuickTypeOpen:(BOOL)isAutoFillQuickTypeOpen
                    onDemandUiProvider:(MacCompositeKeyDeterminerOnDemandUIProviderBlock)onDemandUiProvider {
    self = [super init];
    
    if (self) {
        self.onDemandUiProvider = onDemandUiProvider;
        self.database = database;
        self.isNativeAutoFillAppExtensionOpen = isNativeAutoFillAppExtensionOpen;
        self.isAutoFillQuickTypeOpen = isAutoFillQuickTypeOpen;
    }
    
    return self;
}

- (NSViewController*)viewController {
    return self.onDemandUiProvider();
}

- (void)getCkfs:(CompositeKeyDeterminedBlock)completion {
    if ( self.bioOrWatchUnlockIsPossible ) {
        NSLog(@"MacCompositeKeyDeterminer::getCkfs. Convenience Possible...");
        [self getCkfsWithBiometrics:self.contextAwareKeyFileBookmark
               yubiKeyConfiguration:self.database.yubiKeyConfiguration
                      allowFallback:YES
                         completion:completion];
    }
    else {
        NSLog(@"MacCompositeKeyDeterminer::getCkfs. Convenience Possible...");
        [self getCkfsManually:completion];
    }
}

- (void)getCkfsManually:(CompositeKeyDeterminedBlock)completion {
    NSLog(@"MacCompositeKeyDeterminer::getCkfsManually...");

    dispatch_async(dispatch_get_main_queue(), ^{
        [self _getCkfsWithManualUnlock:completion];
    });
}

- (void)getCkfsWithBiometrics:(NSString *)keyFileBookmark
         yubiKeyConfiguration:(YubiKeyConfiguration *)yubiKeyConfiguration
                   completion:(CompositeKeyDeterminedBlock)completion {
    [self getCkfsWithBiometrics:keyFileBookmark yubiKeyConfiguration:yubiKeyConfiguration allowFallback:NO completion:completion];
}

- (void)getCkfsWithBiometrics:(NSString *)keyFileBookmark
         yubiKeyConfiguration:(YubiKeyConfiguration *)yubiKeyConfiguration
                allowFallback:(BOOL)allowFallback
                   completion:(CompositeKeyDeterminedBlock)completion {
    NSLog(@"MacCompositeKeyDeterminer::getCkfsWithBiometrics...");

    dispatch_async(dispatch_get_main_queue(), ^{
        [self _getCkfsWithBiometrics:keyFileBookmark yubiKeyConfiguration:yubiKeyConfiguration allowFallback:allowFallback completion:completion];
    });
}

- (void)_getCkfsWithManualUnlock:(CompositeKeyDeterminedBlock)completion {
    ManualCredentialsEntry* mce = [[ManualCredentialsEntry alloc] initWithNibName:@"ManualCredentialsEntry" bundle:nil];
    mce.databaseUuid = self.database.uuid;
    mce.isNativeAutoFillAppExtensionOpen = self.isNativeAutoFillAppExtensionOpen;
    
    mce.onDone = ^(BOOL userCancelled, NSString * _Nullable password, NSString * _Nullable keyFileBookmark, YubiKeyConfiguration * _Nullable yubiKeyConfiguration) {
        AppDelegate* appDelegate = NSApplication.sharedApplication.delegate;
        appDelegate.isRequestingAutoFillManualCredentialsEntry = NO;

        if (userCancelled) {
            completion(kGetCompositeKeyResultUserCancelled, nil, NO, nil);
        }
        else {
            [self getCkfsWithPassword:password
                      keyFileBookmark:keyFileBookmark
                 yubiKeyConfiguration:yubiKeyConfiguration
                      fromConvenience:NO
                           completion:completion];
        }
    };
    
    if ( !self.createWindowForManualCredentialsEntry ) {
        [self.viewController presentViewControllerAsSheet:mce];
    }
    else {
        
        
        
        AppDelegate* appDelegate = NSApplication.sharedApplication.delegate;
        appDelegate.isRequestingAutoFillManualCredentialsEntry = YES; 
        
        

        NSWindow* window = [NSWindow windowWithContentViewController:mce];
        [window setLevel:NSFloatingWindowLevel];

        NSWindowController* wc = [[NSWindowController alloc] initWithWindow:window];
        [wc showWindow:nil];
        [window center];
        
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp arrangeInFront:nil];
        
        [window makeKeyAndOrderFront:nil];
    }
}

- (void)_getCkfsWithBiometrics:(NSString *)keyFileBookmark
          yubiKeyConfiguration:(YubiKeyConfiguration *)yubiKeyConfiguration
                 allowFallback:(BOOL)allowFallback
                    completion:(CompositeKeyDeterminedBlock)completion {
    if ( !self.bioOrWatchUnlockIsPossible ) { 
        NSLog(@"Biometrics/Watch not possible...");
        
        if ( allowFallback ) {
            NSLog(@"Falling back to manual unlock...");
            [self getCkfsManually:completion];
        }
        return;
    }
    
    NSString* localizedFallbackTitle = allowFallback ? NSLocalizedString(@"safes_vc_unlock_manual_action", @"Manual Unlock") : @"";

    
    
    
    
    AutoFillLoadingVC *requiredDummyAutoFillSheet = nil;
    if ( self.isNativeAutoFillAppExtensionOpen ) {
        NSStoryboard* sb = [NSStoryboard storyboardWithName:@"AutoFillLoading" bundle:nil];
        requiredDummyAutoFillSheet = (AutoFillLoadingVC*)[sb instantiateInitialController];
        requiredDummyAutoFillSheet.onCancelButton = ^{
            completion(kGetCompositeKeyResultUserCancelled, nil, NO, nil);
        };
        [self.viewController presentViewControllerAsSheet:requiredDummyAutoFillSheet];
    }
    
    [BiometricIdHelper.sharedInstance authorize:localizedFallbackTitle
                                       database:self.database
                                     completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if ( requiredDummyAutoFillSheet ) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self.viewController dismissViewController:requiredDummyAutoFillSheet];
                });
            }
            
            if(success) {
                [self getCkfsWithPassword:self.database.conveniencePassword
                          keyFileBookmark:keyFileBookmark
                     yubiKeyConfiguration:yubiKeyConfiguration
                          fromConvenience:YES
                               completion:completion];
            }
            else {
                if( allowFallback && error && error.code == LAErrorUserFallback ) {
                    NSLog(@"User requested fallback. Falling back to manual unlock...");
                    [self getCkfsManually:completion];
                }
                else {
                    BOOL cancelled = NO;
                    if( error && (error.code == LAErrorUserCancel || error.code == StrongboxErrorCodes.macOSBiometricInProgressOrImpossible)) {
                        cancelled = YES;
                    }
                    completion(cancelled ? kGetCompositeKeyResultUserCancelled : kGetCompositeKeyResultError, nil, NO, error);
                }
            }
        });
    }];
}

- (void)getCkfsWithExplicitPassword:(NSString *)password
                    keyFileBookmark:(NSString *)keyFileBookmark
               yubiKeyConfiguration:(YubiKeyConfiguration *)yubiKeyConfiguration
                         completion:(CompositeKeyDeterminedBlock)completion {
    [self getCkfsWithPassword:password
              keyFileBookmark:keyFileBookmark
         yubiKeyConfiguration:yubiKeyConfiguration
              fromConvenience:NO
                   completion:completion];
}

- (void)getCkfsWithPassword:(NSString *)password
            keyFileBookmark:(NSString *)keyFileBookmark
       yubiKeyConfiguration:(YubiKeyConfiguration *)yubiKeyConfiguration
            fromConvenience:(BOOL)fromConvenience
                 completion:(CompositeKeyDeterminedBlock)completion {
    NSError* error;
    CompositeKeyFactors* ckf = [self getCkfsWithSelectedUiFactors:password
                                                  keyFileBookmark:keyFileBookmark
                                             yubiKeyConfiguration:yubiKeyConfiguration
                                                  fromConvenience:NO
                                                            error:&error];
    
    if( !ckf || error) {
        completion(kGetCompositeKeyResultError, nil, fromConvenience, error);
    }
    else {
        completion(kGetCompositeKeyResultSuccess, ckf, fromConvenience, error);
    }
}



- (CompositeKeyFactors*)getCkfsWithSelectedUiFactors:(NSString*)password
                                     keyFileBookmark:(NSString *)keyFileBookmark
                                yubiKeyConfiguration:(YubiKeyConfiguration *)yubiKeyConfiguration
                                     fromConvenience:(BOOL)fromConvenience
                                               error:(NSError**)outError {
    DatabaseFormat formatKeyFileHint = keyFileBookmark ? [self getKeyFileDatabaseFormat] : kKeePass4;

    CompositeKeyFactors* ret = [MacCompositeKeyDeterminer getCkfsWithConfigs:password
                                                             keyFileBookmark:keyFileBookmark
                                                        yubiKeyConfiguration:yubiKeyConfiguration
                                                          onDemandUiProvider:self.onDemandUiProvider
                                                           formatKeyFileHint:formatKeyFileHint
                                                                       error:outError];
    
    
    if ( ret == nil && fromConvenience ) {
        NSLog(@"Could not get CKFs with Convenience Unlock. Clearing Secure Convenience Items");

        self.database.conveniencePassword = nil;
        self.database.autoFillConvenienceAutoUnlockPassword = nil;
        self.database.conveniencePasswordHasBeenStored = NO;
    }
    
    
    
    if ( ret != nil ) {
        BOOL rememberKeyFile = !Settings.sharedInstance.doNotRememberKeyFile;
        
        BOOL keyFileChanged = ( !rememberKeyFile && self.contextAwareKeyFileBookmark != nil ) || ((!(self.contextAwareKeyFileBookmark == nil && keyFileBookmark == nil)) && (![self.contextAwareKeyFileBookmark isEqual:keyFileBookmark]));
        BOOL yubikeyChanged = (!(self.database.yubiKeyConfiguration == nil && yubiKeyConfiguration == nil)) && (![self.database.yubiKeyConfiguration isEqual:yubiKeyConfiguration]);
        
        if( keyFileChanged || yubikeyChanged ) {
            NSString* temp = rememberKeyFile ? keyFileBookmark : nil;
            
            if ( self.isNativeAutoFillAppExtensionOpen ) {
                self.database.autoFillKeyFileBookmark = temp;
            }
            else {
                self.database.keyFileBookmark = temp;
            }
            
            self.database.yubiKeyConfiguration = yubiKeyConfiguration;
        }
    }
    
    return ret;
}



+ (CompositeKeyFactors*)getCkfsWithConfigs:(NSString*)password
                           keyFileBookmark:(NSString*)keyFileBookmark
                      yubiKeyConfiguration:(YubiKeyConfiguration*)yubiKeyConfiguration
      hardwareKeyInteractionViewController:(NSViewController*)hardwareKeyInteractionViewController
                         formatKeyFileHint:(DatabaseFormat)formatKeyFileHint
                                     error:(NSError**)outError {
    return [MacCompositeKeyDeterminer getCkfsWithConfigs:password
                                         keyFileBookmark:keyFileBookmark
                                    yubiKeyConfiguration:yubiKeyConfiguration
                                      onDemandUiProvider:^NSViewController * _Nonnull{
        return hardwareKeyInteractionViewController;
    } formatKeyFileHint:formatKeyFileHint error:outError];
}

+ (CompositeKeyFactors*)getCkfsWithConfigs:(NSString*)password
                           keyFileBookmark:(NSString*)keyFileBookmark
                      yubiKeyConfiguration:(YubiKeyConfiguration*)yubiKeyConfiguration
                        onDemandUiProvider:(MacCompositeKeyDeterminerOnDemandUIProviderBlock)onDemandUiProvider
                         formatKeyFileHint:(DatabaseFormat)formatKeyFileHint
                                     error:(NSError**)outError {
    NSData* keyFileDigest = nil;

    if( keyFileBookmark ) {
        NSError *keyFileParseError;
        keyFileDigest = [KeyFileParser getDigestFromBookmark:keyFileBookmark
                                             keyFileFileName:nil
                                                      format:formatKeyFileHint
                                                       error:&keyFileParseError];
                
        if( keyFileDigest == nil ) {
            NSLog(@"WARNWARN: Could not read Key File [%@]", keyFileParseError);
            
            if (outError) {
                *outError = keyFileParseError;
            }
            
            return nil;
        }
    }

    if ( yubiKeyConfiguration == nil ) {
        return [CompositeKeyFactors password:password keyFileDigest:keyFileDigest];
    }
    else {
        return [MacCompositeKeyDeterminer getCkfsWithPassword:password
                                                keyFileDigest:keyFileDigest
                                         yubiKeyConfiguration:yubiKeyConfiguration
                                           onDemandUiProvider:onDemandUiProvider
                                                        error:outError];
    }
}

+ (CompositeKeyFactors *)getCkfsWithPassword:(NSString *)password
                               keyFileDigest:(NSData *)keyFileDigest
                        yubiKeyConfiguration:(YubiKeyConfiguration *)yubiKeyConfiguration
                          onDemandUiProvider:(MacCompositeKeyDeterminerOnDemandUIProviderBlock)onDemandUiProvider
                                       error:(NSError **)error {
    NSInteger slot = yubiKeyConfiguration.slot;
    
    return [CompositeKeyFactors password:password
                           keyFileDigest:keyFileDigest
                               yubiKeyCR:^(NSData * _Nonnull challenge, YubiKeyCRResponseBlock  _Nonnull completion) {
        [MacHardwareKeyManager.sharedInstance compositeKeyFactorCr:challenge
                                                              slot:slot
                                                        completion:completion
                                            onDemandWindowProvider:^NSWindow * _Nonnull{
            NSViewController* vc = onDemandUiProvider();
            return vc.view.window;
        }];
    }];
}

- (DatabaseFormat)getKeyFileDatabaseFormat {
    DatabaseFormat format = self.database.likelyFormat;
    NSURL* url = [WorkingCopyManager.sharedInstance getLocalWorkingCache:self.database.uuid];
    if (url) {
        format = [Serializator getDatabaseFormat:url];
    }
    else {
        
        NSLog(@"🔴 WARNWARN: Could not read working copy to check Key File Format");
    }
    return format;
}

- (BOOL)bioOrWatchUnlockIsPossible {
    return [MacCompositeKeyDeterminer bioOrWatchUnlockIsPossible:self.database];
}

+ (BOOL)bioOrWatchUnlockIsPossible:(MacDatabasePreferences*)database {
    if ( !database ) {
        return NO;
    }
    
    BOOL watchAvailable = BiometricIdHelper.sharedInstance.isWatchUnlockAvailable;
    BOOL touchAvailable = BiometricIdHelper.sharedInstance.isTouchIdUnlockAvailable;
    BOOL touchEnabled = (database.isTouchIdEnabled && touchAvailable);
    BOOL watchEnabled = (database.isWatchUnlockEnabled && watchAvailable);
    BOOL methodEnabled = touchEnabled || watchEnabled;
    BOOL passwordAvailable = database.conveniencePasswordHasBeenStored;
    BOOL featureAvailable = Settings.sharedInstance.isPro;
    [database triggerPasswordExpiry];
    BOOL expired = database.conveniencePasswordHasExpired;
    BOOL possible = methodEnabled && featureAvailable && passwordAvailable && !expired;
    

    
    return possible;
}

- (NSString*)contextAwareKeyFileBookmark {
    return self.isNativeAutoFillAppExtensionOpen ? self.database.autoFillKeyFileBookmark : self.database.keyFileBookmark;
}

@end
