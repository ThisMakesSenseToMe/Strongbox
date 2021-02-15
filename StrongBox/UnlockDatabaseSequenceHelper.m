//
//  OpenSafeSequenceHelper.m
//  Strongbox-iOS
//
//  Created by Mark on 12/10/2018.
//  Copyright © 2014-2021 Mark McGuill. All rights reserved.
//

#import "UnlockDatabaseSequenceHelper.h"
#import "IOsUtils.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import "Alerts.h"
#import "SVProgressHUD.h"
#import "KeyFileParser.h"
#import "Utils.h"
#import "PinEntryController.h"
#import "AutoFillManager.h"
#import "CASGTableViewController.h"
#import "AddNewSafeHelper.h"
#import "FileManager.h"
#import "StrongboxUIDocument.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "BiometricsManager.h"
#import "BookmarksHelper.h"
#import "YubiManager.h"
#import "SharedAppAndAutoFillSettings.h"
#import "AutoFillSettings.h"
#import "Kdbx4Database.h"
#import "Kdbx4Serialization.h"
#import "KeePassCiphers.h"
#import "NSDate+Extensions.h"
#import "FilesAppUrlBookmarkProvider.h"

#import <FileProvider/FileProvider.h>
#import "VirtualYubiKeys.h"

#ifndef IS_APP_EXTENSION
#import "OfflineDetector.h"
#import "ISMessages/ISMessages.h"
#endif

#import <Foundation/FoundationErrors.h>
#import "Serializator.h"

#import "CompositeKeyDeterminer.h"
#import "Platform.h"
#import "DuressActionHelper.h"

#import "SyncManager.h"
#import "WorkingCopyManager.h"

@interface UnlockDatabaseSequenceHelper () <UIDocumentPickerDelegate>



@property (nonnull) UIViewController* viewController;
@property (nonnull) SafeMetaData* database;
@property BOOL isAutoFillOpen;
@property BOOL offlineExplicitlyRequested;
@property (nonnull) UnlockDatabaseCompletionBlock completion;



@property BOOL unlockedWithConvenienceFactors;
@property CompositeKeyFactors* relocationFactors;

@end

@implementation UnlockDatabaseSequenceHelper

+ (instancetype)helperWithViewController:(UIViewController *)viewController database:(SafeMetaData *)database {
    return [self helperWithViewController:viewController database:database isAutoFillOpen:NO openOffline:NO];
}

+ (instancetype)helperWithViewController:(UIViewController*)viewController
                                database:(SafeMetaData*)database
                          isAutoFillOpen:(BOOL)isAutoFillOpen
                             openOffline:(BOOL)openOffline {
    return [[UnlockDatabaseSequenceHelper alloc] initWithViewController:viewController
                                                                   safe:database
                                                         isAutoFillOpen:isAutoFillOpen
                                                            openOffline:openOffline];
}

- (instancetype)initWithViewController:(UIViewController*)viewController
                                  safe:(SafeMetaData*)safe
                        isAutoFillOpen:(BOOL)isAutoFillOpen
                           openOffline:(BOOL)openOffline {
    self = [super init];
    if (self) {
        self.viewController = viewController;
        self.database = safe;
        self.isAutoFillOpen = isAutoFillOpen;
        self.offlineExplicitlyRequested = openOffline;
    }
    
    return self;
}

- (void)beginUnlockSequence:(UnlockDatabaseCompletionBlock)completion {
    return [self beginUnlockSequence:NO biometricPreCleared:NO noConvenienceUnlock:NO completion:completion];
}

- (void)beginUnlockSequence:(BOOL)isAutoFillQuickTypeOpen
        biometricPreCleared:(BOOL)biometricPreCleared
        noConvenienceUnlock:(BOOL)noConvenienceUnlock
                 completion:(UnlockDatabaseCompletionBlock)completion {
    self.completion = completion;
    
    CompositeKeyDeterminer* determiner = [CompositeKeyDeterminer determinerWithViewController:self.viewController
                                                                                     database:self.database
                                                                               isAutoFillOpen:self.isAutoFillOpen
                                                                      isAutoFillQuickTypeOpen:isAutoFillQuickTypeOpen
                                                                          biometricPreCleared:biometricPreCleared
                                                                          noConvenienceUnlock:noConvenienceUnlock];
    
    [determiner getCredentials:^(GetCompositeKeyResult result, CompositeKeyFactors * _Nullable factors, BOOL fromConvenience, NSError * _Nullable error) {
        if (result == kGetCompositeKeyResultSuccess) {
            self.unlockedWithConvenienceFactors = fromConvenience;
            [self beginUnlockWithCredentials:factors];
        }
        else if (result == kGetCompositeKeyResultDuressIndicated ) {
            [DuressActionHelper performDuressAction:self.viewController database:self.database isAutoFillOpen:self.isAutoFillOpen completion:self.completion];
        }
        else if (result == kGetCompositeKeyResultError) {
            self.completion(kUnlockDatabaseResultError, nil, error);
        }
        else {
            self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
        }
    }];
}



- (BOOL)userIsLikelyOffline {
#ifndef IS_APP_EXTENSION
    return OfflineDetector.sharedInstance.isOffline;
#endif
    return NO;
}

- (void)beginUnlockWithCredentials:(CompositeKeyFactors*)factors {
    NSDate* localCopyModDate;
    NSURL* localCopyUrl = [WorkingCopyManager.sharedInstance getLocalWorkingCache:self.database modified:&localCopyModDate];

    BOOL isPro = SharedAppAndAutoFillSettings.sharedInstance.isProOrFreeTrial;

    if(self.isAutoFillOpen || self.offlineExplicitlyRequested) {
        if(localCopyUrl == nil) {
            [Alerts warn:self.viewController
                   title:NSLocalizedString(@"open_sequence_couldnt_open_local_title", @"Could Not Open Offline")
                 message:NSLocalizedString(@"open_sequence_couldnt_open_local_message", @"Could not open Strongbox's local copy of this database. A online sync is required.")];
            self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
            return;
        }
        
        BOOL forceReadOnly = !self.isAutoFillOpen && !isPro;
        [self unlockLocalCopy:factors forceReadOnly:forceReadOnly offline:YES];
        return;
    }

    BOOL userLikelyOffline = [self userIsLikelyOffline];
    BOOL immediateOfflineOfferIfOffline = self.database.immediateOfflineOfferIfOfflineDetected;
    BOOL offlinePossible = localCopyUrl != nil;
    BOOL notLocalDevice = self.database.storageProvider != kLocalDevice;
    
    if ( userLikelyOffline && immediateOfflineOfferIfOffline && offlinePossible && notLocalDevice ) {
        NSString* primaryStorageDisplayName = [SyncManager.sharedInstance getPrimaryStorageDisplayName:self.database];
        NSString* loc1 = NSLocalizedString(@"open_sequence_user_looks_offline_open_local_ro_fmt", "It looks like you may be offline and '%@' may not be reachable. Would you like to open in offline mode instead?\n\nNB: You can also edit offline in the Pro version.");
        NSString* loc2 = NSLocalizedString(@"open_sequence_user_looks_offline_open_local_fmt", "It looks like you may be offline and '%@' may not be reachable. Would you like to open in offline mode instead?");

        NSString* loc = isPro ? loc2 : loc1;
        NSString* message = [NSString stringWithFormat:loc, primaryStorageDisplayName];
        
        [Alerts twoOptionsWithCancel:self.viewController
                               title:NSLocalizedString(@"open_sequence_yesno_use_local_copy_title", @"Open Offline?")
                             message:message
                   defaultButtonText:NSLocalizedString(@"open_sequence_yes_use_local_copy_option", @"Yes, Open Offline")
                    secondButtonText:NSLocalizedString(@"open_sequence_yesno_use_offline_cache_no_try_connect_option", @"No, Try to connect anyway")
                              action:^(int response) {
            if (response == 0) { 
                [self unlockLocalCopy:factors forceReadOnly:!isPro offline:YES];
            }
            else if (response == 1) { 
                [self syncAndUnlock:factors];
            }
            else {
                self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
            }
        }];
    }
    else {
        [self syncAndUnlock:factors];
    }
}

- (void)syncAndUnlock:(CompositeKeyFactors*)factors {
    [self syncAndUnlock:YES factors:factors];
}

- (void)syncAndUnlock:(BOOL)join factors:(CompositeKeyFactors*)factors {
    dispatch_async(dispatch_get_main_queue(), ^{
        [SVProgressHUD showWithStatus:NSLocalizedString(@"storage_provider_status_syncing", @"Syncing...")];
    });

    [SyncManager.sharedInstance sync:self.database
                       interactiveVC:self.viewController
                                 key:factors
                                join:join
                          completion:^(SyncAndMergeResult result, BOOL localWasChanged, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD dismiss];
             
            if (result == kSyncAndMergeResultUserInteractionRequired) {
                
                [self syncAndUnlock:NO factors:factors];
            }
            else if (result == kSyncAndMergeResultUserCancelled) {
                
                self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
            }
            else if (result == kSyncAndMergeError) {
                [self handleSyncAndMergeError:factors error:error];
            }
            else if ( result == kSyncAndMergeSuccess || result == kSyncAndMergeUserPostponedSync ) {
                
                [self unlockLocalCopy:factors forceReadOnly:NO offline:NO];
            }
            else {
                NSLog(@"WARNWARN: Unknown response from Sync: %lu", (unsigned long)result);
                self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
            }
        });
    }];
}

- (void)handleSyncAndMergeError:(CompositeKeyFactors*)factors error:(NSError*)error {
    NSLog(@"Unlock Interactive Sync Error: [%@]", error);
    if (self.database.storageProvider == kFilesAppUrlBookmark && [self errorIndicatesWeShouldAskUseToRelocateDatabase:error]) {
        [self askAboutRelocatingDatabase:factors];
    }
    else {
        NSString* message = NSLocalizedString(@"open_sequence_storage_provider_error_open_local_ro_instead", @"A sync error occured. If this happens repeatedly you should try removing and re-adding your database.\n\n%@\nWould you like to open Strongbox's local copy in read-only mode instead?");
        NSString* viewSyncError = NSLocalizedString(@"open_sequence_storage_provider_view_sync_error_details", @"View Error Details");

        [Alerts twoOptionsWithCancel:self.viewController
                               title:NSLocalizedString(@"open_sequence_storage_provider_error_title", @"Sync Error")
                             message:message
                   defaultButtonText:NSLocalizedString(@"open_sequence_yes_use_local_copy_option", @"Yes, Open Offline")
                    secondButtonText:viewSyncError
                              action:^(int response) {
            if (response == 0) {
                BOOL isPro = SharedAppAndAutoFillSettings.sharedInstance.isProOrFreeTrial;
                [self unlockLocalCopy:factors forceReadOnly:!isPro offline:YES];
            }
            else if (response == 1) { 
                self.completion(kUnlockDatabaseResultViewDebugSyncLogRequested, nil, nil);
            }
            else {
                self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
            }
        }];
    }
}

- (void)unlockLocalCopy:(CompositeKeyFactors*)factors forceReadOnly:(BOOL)forceReadOnly offline:(BOOL)offline {
    DatabaseUnlocker* unlocker = [DatabaseUnlocker unlockerForDatabase:self.database viewController:self.viewController forceReadOnly:forceReadOnly isAutoFillOpen:self.isAutoFillOpen offlineMode:offline];
    [unlocker unlockLocalWithKey:factors keyFromConvenience:self.unlockedWithConvenienceFactors completion:self.completion];
}



static UnlockDatabaseSequenceHelper *sharedInstance = nil; 

- (BOOL)errorIndicatesWeShouldAskUseToRelocateDatabase:(NSError*)error {
    if (@available(iOS 11.0, *)) {
        return (error.code == NSFileProviderErrorNoSuchItem || 
                error.code == NSFileReadNoPermissionError ||   
                error.code == NSFileReadNoSuchFileError ||     
                error.code == NSFileNoSuchFileError);
    } else {
        return NO;
    }
}

- (void)askAboutRelocatingDatabase:(CompositeKeyFactors*)factors {
    NSString* message = NSLocalizedString(@"open_sequence_storage_provider_try_relocate_files_db_message", @"Strongbox is having trouble locating your database. This can happen sometimes especially after iOS updates or with some 3rd party providers (e.g.Nextcloud).\n\nYou now need to tell Strongbox where to locate it. Alternatively you can open Strongbox's local copy and fix this later.\n\nFor Nextcloud please use WebDAV instead...");
    
    NSString* relocateDatabase = NSLocalizedString(@"open_sequence_storage_provider_try_relocate_files_db", @"Locate Database...");

    BOOL isPro = SharedAppAndAutoFillSettings.sharedInstance.isProOrFreeTrial;

    NSString* openOfflineText = isPro ? NSLocalizedString(@"open_sequence_use_local_copy_option", @"Open Offline") : NSLocalizedString(@"open_sequence_use_local_copy_option_ro", @"Open Offline (Read-Only)");
    
    [Alerts twoOptionsWithCancel:self.viewController
                           title:NSLocalizedString(@"open_sequence_storage_provider_error_title", @"Sync Error")
                         message:message
               defaultButtonText:relocateDatabase
                secondButtonText:openOfflineText
                          action:^(int response) {
        if (response == 0) {
            [self onRelocateFilesBasedDatabase:factors];
        }
        else if (response == 1) {
            [self unlockLocalCopy:factors forceReadOnly:!isPro offline:YES];
        }
        else {
            self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
        }
    }];
}

- (void)onRelocateFilesBasedDatabase:(CompositeKeyFactors*)factors {
    
    
    sharedInstance = self;
    self.relocationFactors = factors;
    
    UIDocumentPickerViewController *vc = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[(NSString*)kUTTypeItem] inMode:UIDocumentPickerModeOpen];
    vc.delegate = self; 
    vc.modalPresentationStyle = UIModalPresentationFormSheet;
    
    [self.viewController presentViewController:vc animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    sharedInstance = nil;
    self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSLog(@"didPickDocumentsAtURLs: %@", urls);
    
    NSURL* url = [urls objectAtIndex:0];

    #pragma GCC diagnostic push
    #pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    [self documentPicker:controller didPickDocumentAtURL:url];
    #pragma GCC diagnostic pop
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-implementations"
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url { 
    StrongboxUIDocument *document = [[StrongboxUIDocument alloc] initWithFileURL:url];
    if (!document) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self readReselectedFilesDatabase:NO data:nil url:url];
        });
        return;
    }

    [document openWithCompletionHandler:^(BOOL success) {
        NSData* data = document.data;
        
        [document closeWithCompletionHandler:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self readReselectedFilesDatabase:success data:data url:url];
        });
    }];
    
    sharedInstance = nil;
}
#pragma GCC diagnostic pop

- (void)readReselectedFilesDatabase:(BOOL)success data:(NSData*)data url:(NSURL*)url {
    if(!success || !data) {
        [Alerts warn:self.viewController
               title:@"Error Opening This Database"
             message:@"Could not access this file."];
        self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
    }
    else {
        NSError* error;
        
        if (![Serializator isValidDatabaseWithPrefix:data error:&error]) {
            [Alerts error:self.viewController
                    title:[NSString stringWithFormat:NSLocalizedString(@"open_sequence_invalid_database_filename_fmt", @"Invalid Database - [%@]"), url.lastPathComponent]
                    error:error];
            self.completion(kUnlockDatabaseResultUserCancelled, nil, nil);
            return;
        }
        
        if([url.lastPathComponent compare:self.database.fileName] != NSOrderedSame) {
            [Alerts yesNo:self.viewController
                    title:NSLocalizedString(@"open_sequence_database_different_filename_title",@"Different Filename")
                  message:NSLocalizedString(@"open_sequence_database_different_filename_message",@"This doesn't look like it's the right file because the filename looks different than the one you originally added. Do you want to continue?")
                   action:^(BOOL response) {
                       if(response) {
                           [self updateFilesBookmarkWithRelocatedUrl:url];
                       }
                   }];
        }
        else {
            [self updateFilesBookmarkWithRelocatedUrl:url];
        }
    }
}

- (void)updateFilesBookmarkWithRelocatedUrl:(NSURL*)url {
    NSError* error;
    NSData* bookMark = [BookmarksHelper getBookmarkDataFromUrl:url error:&error];
    
    if (error) {
        [Alerts error:self.viewController
                title:NSLocalizedString(@"open_sequence_error_could_not_bookmark_file", @"Could not bookmark this file")
                error:error];
        self.completion(kUnlockDatabaseResultError, nil, nil);
    }
    else {
        NSString* identifier = [FilesAppUrlBookmarkProvider.sharedInstance getJsonFileIdentifier:bookMark];

        self.database.fileIdentifier = identifier;
        [SafesList.sharedInstance update:self.database];
        
        [self syncAndUnlock:YES factors:self.relocationFactors]; 
    }
}




@end
