//
//  CredentialProviderViewController.m
//  Strongbox AutoFill
//
//  Created by Mark on 11/10/2018.
//  Copyright © 2014-2021 Mark McGuill. All rights reserved.
//

#import "CredentialProviderViewController.h"
#import "SafesList.h"
#import "NSArray+Extensions.h"
#import "SafesListTableViewController.h"
#import "Alerts.h"
#import "mach/mach.h"
#import "QuickTypeRecordIdentifier.h"
#import "OTPToken+Generation.h"
#import "Utils.h"
#import "AutoFillManager.h"
#import "AutoFillSettings.h"
#import "LocalDeviceStorageProvider.h"
#import "ClipboardManager.h"
#import "SyncManager.h"
#import "Model.h"
#import "CompositeKeyDeterminer.h"
#import "DatabaseUnlocker.h"
#import "DuressActionHelper.h"
#import "WorkingCopyManager.h"

@interface CredentialProviderViewController () <UIAdaptivePresentationControllerDelegate>

@property (nonatomic, strong) UINavigationController* databasesListNavController;
@property (nonatomic, strong) NSArray<ASCredentialServiceIdentifier *> * serviceIdentifiers;

@property BOOL quickTypeMode;

@end

@implementation CredentialProviderViewController



- (void)provideCredentialWithoutUserInteractionForIdentity:(ASPasswordCredentialIdentity *)credentialIdentity {
    NSLog(@"provideCredentialWithoutUserInteractionForIdentity: [%@]", credentialIdentity);
    [self exitWithUserInteractionRequired];
}

- (void)prepareInterfaceToProvideCredentialForIdentity:(ASPasswordCredentialIdentity *)credentialIdentity {
    NSLog(@"prepareInterfaceToProvideCredentialForIdentity = %@", credentialIdentity);
    
    BOOL lastRunGood = [self enterWithLastCrashCheck:YES];
    
    if (!lastRunGood) {
        [self showLastRunCrashedMessage:^{
            [self initializeQuickType:credentialIdentity];
        }];
    }
    else {
        [self initializeQuickType:credentialIdentity];
    }
}

- (void)initializeQuickType:(ASPasswordCredentialIdentity *)credentialIdentity {
    QuickTypeRecordIdentifier* identifier = [QuickTypeRecordIdentifier fromJson:credentialIdentity.recordIdentifier];
    NSLog(@"prepareInterfaceToProvideCredentialForIdentity: [%@] => Found: [%@]", credentialIdentity, identifier);
    
    if(identifier) {
        SafeMetaData* safe = [SafesList.sharedInstance.snapshot firstOrDefault:^BOOL(SafeMetaData * _Nonnull obj) {
            return [obj.uuid isEqualToString:identifier.databaseId];
        }];
        
        if(safe) {
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self unlockDatabaseForQuickType:safe identifier:identifier];
            });
        }
        else {
            [AutoFillManager.sharedInstance clearAutoFillQuickTypeDatabase];
            
            [Alerts info:self
                   title:NSLocalizedString(@"autofill_error_unknown_db_title", @"Strongbox: Unknown Database")
                 message:NSLocalizedString(@"autofill_error_unknown_db_message", @"This appears to be a reference to an older Strongbox database which can no longer be found. Strongbox's QuickType AutoFill database has now been cleared, and so you will need to reopen your databases to refresh QuickType AutoFill.")
              completion:^{
                [self exitWithErrorOccurred:[Utils createNSError:@"Could not find this database in Strongbox any longer." errorCode:-1]];
            }];
        }
    }
    else {
        [AutoFillManager.sharedInstance clearAutoFillQuickTypeDatabase];
        
        [Alerts info:self
               title:NSLocalizedString(@"autofill_error_unknown_item_title", @"Strongbox: Error Locating Entry")
             message:NSLocalizedString(@"autofill_error_unknown_item_message", @"Strongbox could not find this entry, it is possibly stale. Strongbox's QuickType AutoFill database has now been cleared, and so you will need to reopen your databases to refresh QuickType AutoFill.")
          completion:^{
            
            [self exitWithErrorOccurred:[Utils createNSError:@"Could not find this record in Strongbox any longer." errorCode:-1]];
        }];
    }
}

- (void)unlockDatabaseForQuickType:(SafeMetaData*)safe identifier:(QuickTypeRecordIdentifier*)identifier {
    CompositeKeyDeterminer* keyDeterminer = [CompositeKeyDeterminer determinerWithViewController:self database:safe isAutoFillOpen:YES isAutoFillQuickTypeOpen:YES biometricPreCleared:NO noConvenienceUnlock:NO];
    [keyDeterminer getCredentials:^(GetCompositeKeyResult result, CompositeKeyFactors * _Nullable factors, BOOL fromConvenience, NSError * _Nullable error) {
        if (result == kGetCompositeKeyResultSuccess) {
            AutoFillSettings.sharedInstance.autoFillExitedCleanly = NO; 
            
            DatabaseUnlocker* unlocker = [DatabaseUnlocker unlockerForDatabase:safe viewController:self forceReadOnly:NO isAutoFillOpen:YES offlineMode:YES];
            [unlocker unlockLocalWithKey:factors keyFromConvenience:fromConvenience completion:^(UnlockDatabaseResult result, Model * _Nullable model, NSError * _Nullable error) {
                AutoFillSettings.sharedInstance.autoFillExitedCleanly = YES;
                
                [self onUnlockDone:result model:model identifier:identifier error:error];
            }];
        }
        else if (result == kGetCompositeKeyResultError) {
            [self messageErrorAndExit:error];
        }
        else if (result == kGetCompositeKeyResultDuressIndicated) {
            [DuressActionHelper performDuressAction:self database:safe isAutoFillOpen:NO completion:^(UnlockDatabaseResult result, Model * _Nullable model, NSError * _Nullable error) { 
                [self onUnlockDone:result model:model identifier:identifier error:error];
            }];
        }
        else {
            [self cancel:nil];
        }
    }];
}

- (void)onUnlockDone:(UnlockDatabaseResult)result model:(Model * _Nullable)model identifier:(QuickTypeRecordIdentifier*)identifier error:(NSError * _Nullable)error {
    NSLog(@"AutoFill: Open Database: Model=[%@] - Error = [%@]", model, error);
    
    if(result == kUnlockDatabaseResultSuccess) {
        [self onUnlockedDatabase:model quickTypeIdentifier:identifier];
    }
    else if(result == kUnlockDatabaseResultUserCancelled || result == kUnlockDatabaseResultViewDebugSyncLogRequested) {
        [self cancel:nil]; 
    }
    else if (result == kUnlockDatabaseResultIncorrectCredentials) {
        
        NSLog(@"INCORRECT CREDENTIALS - kUnlockDatabaseResultIncorrectCredentials");
        [self exitWithErrorOccurred:error ? error : [Utils createNSError:@"Could not open database" errorCode:-1]];
    }
    else if (result == kUnlockDatabaseResultError) {
        [self messageErrorAndExit:error];
    }
}

- (void)onUnlockedDatabase:(Model*)model quickTypeIdentifier:(QuickTypeRecordIdentifier*)identifier {
    Node* node = [model.database.effectiveRootGroup.allChildRecords firstOrDefault:^BOOL(Node * _Nonnull obj) {
        return [obj.uuid.UUIDString isEqualToString:identifier.nodeId]; 
    }];
    
    if(node) {
        NSString* user = [model.database dereference:node.fields.username node:node];
        NSString* password = [model.database dereference:node.fields.password node:node];
        
        

        
        
        if(node.fields.otpToken) {
            NSString* value = node.fields.otpToken.password;
            if (value.length) {
                [ClipboardManager.sharedInstance copyStringWithDefaultExpiration:value];
                NSLog(@"Copied TOTP to Pasteboard...");
            }
        }
        
        [self exitWithCredential:user password:password];
    }
    else {
        [AutoFillManager.sharedInstance clearAutoFillQuickTypeDatabase];
        
        [Alerts info:self title:@"Strongbox: Error Locating This Record"
             message:@"Strongbox could not find this record in the database any longer. It is possibly stale. Strongbox's QuickType AutoFill database has now been cleared, and so you will need to reopen your databases to refresh QuickType AutoFill."
          completion:^{
            [self exitWithErrorOccurred:[Utils createNSError:@"Could not find record in database" errorCode:-1]];
        }];
    }
}

- (void)messageErrorAndExit:(NSError*)error {
    [Alerts error:self
            title:NSLocalizedString(@"open_sequence_problem_opening_title", @"There was a problem opening the database.")
            error:error
       completion:^{
        [self exitWithErrorOccurred:error ? error : [Utils createNSError:@"Could not open database" errorCode:-1]];
    }];
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers {
    NSLog(@"prepareCredentialListForServiceIdentifiers = %@ - nav = [%@]", serviceIdentifiers, self.navigationController);
    
    self.serviceIdentifiers = serviceIdentifiers;
    
    BOOL lastRunGood = [self enterWithLastCrashCheck:NO];

    UIStoryboard *mainStoryboard = [UIStoryboard storyboardWithName:@"MainInterface" bundle:nil];
    self.databasesListNavController = [mainStoryboard instantiateViewControllerWithIdentifier:@"SafesListNavigationController"];
    SafesListTableViewController* databasesList = ((SafesListTableViewController*)(self.databasesListNavController.topViewController));
    
    databasesList.rootViewController = self;
    databasesList.lastRunGood = lastRunGood;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if(!self.quickTypeMode) {
        [self showSafesListView];
    }
}

- (void)showSafesListView {
    if(self.presentedViewController) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }
    
    if(!self.databasesListNavController) {
        




            [self exitWithErrorOccurred:[Utils createNSError:@"There was an error loading the Safes List View" errorCode:-1]];

    }
    else {
        [SafesList.sharedInstance reloadIfChangedByOtherComponent];

        SafesListTableViewController* databasesList = ((SafesListTableViewController*)(self.databasesListNavController.topViewController));

        self.databasesListNavController.presentationController.delegate = self;

        if(!databasesList.lastRunGood) {
            [self showLastRunCrashedMessage:^{
                [self presentViewController:self.databasesListNavController animated:NO completion:nil];
            }];
        }
        else {
            [self presentViewController:self.databasesListNavController animated:NO completion:nil];
        }
    }
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    NSLog(@"presentationControllerDidDismiss");
    [self cancel:nil];
}

- (BOOL)autoFillIsPossibleWithSafe:(SafeMetaData*)safeMetaData {
    if(!safeMetaData.autoFillEnabled) {
        return NO;
    }
        
    return [WorkingCopyManager.sharedInstance isLocalWorkingCacheAvailable:safeMetaData modified:nil];
}

- (NSArray<ASCredentialServiceIdentifier *> *)getCredentialServiceIdentifiers {
    return self.serviceIdentifiers;
}

- (IBAction)cancel:(id)sender {
    [self exitWithUserCancelled];
}




- (BOOL)enterWithLastCrashCheck:(BOOL)quickType {
    NSLog(@"Auto-Fill Entered - Quick Type Mode = [%d]", quickType);
    
    self.quickTypeMode = quickType;
    
    BOOL lastRunGood = AutoFillSettings.sharedInstance.autoFillExitedCleanly && AutoFillSettings.sharedInstance.autoFillWroteCleanly;
    
    
    
    
    

    if(!lastRunGood) {
        NSLog(@"Last run of AutoFill did not exit cleanly! Warn User that a crash occurred...");
    }
    
    return lastRunGood;
}

- (void)showLastRunCrashedMessage:(void (^)(void))completion {
    NSLog(@"Exit Clean = %hhd, Wrote Clean = %hhd", AutoFillSettings.sharedInstance.autoFillExitedCleanly, AutoFillSettings.sharedInstance.autoFillWroteCleanly);
    
    NSString* title = NSLocalizedString(@"autofill_did_not_close_cleanly_title", @"AutoFill Crash Occurred");
    NSString* message = NSLocalizedString(@"autofill_did_not_close_cleanly_message", @"It looks like the last time you used AutoFill you had a crash. This is usually due to a memory limitation. Please check your database file size and your Argon2 memory settings (should be <= 64MB).");

    [Alerts info:self title:title message:message completion:completion];

    
    
    AutoFillSettings.sharedInstance.autoFillExitedCleanly = YES;
    AutoFillSettings.sharedInstance.autoFillWroteCleanly = YES;
}

- (void)exitWithUserCancelled {
    NSLog(@"EXIT: User Cancelled");
    AutoFillSettings.sharedInstance.autoFillExitedCleanly = YES;
    
    [self.extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain code:ASExtensionErrorCodeUserCanceled userInfo:nil]];
}

- (void)exitWithUserInteractionRequired {
    NSLog(@"EXIT: User Interaction Required");
    [self.extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain
                                                                      code:ASExtensionErrorCodeUserInteractionRequired
                                                                  userInfo:nil]];
}

- (void)exitWithErrorOccurred:(NSError*)error {
    NSLog(@"EXIT: Error Occured [%@]", error);
    AutoFillSettings.sharedInstance.autoFillExitedCleanly = YES; 
    
    [self.extensionContext cancelRequestWithError:error];
}

- (void)exitWithCredential:(NSString*)username password:(NSString*)password {
    NSLog(@"EXIT: Success");
    AutoFillSettings.sharedInstance.autoFillExitedCleanly = YES;
    
    ASPasswordCredential *credential = [[ASPasswordCredential alloc] initWithUser:username password:password];
    [self.extensionContext completeRequestWithSelectedCredential:credential completionHandler:nil];
}


























@end
