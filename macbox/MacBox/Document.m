//
//  Document.m
//  MacBox
//
//  Created by Mark on 01/08/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "Document.h"
#import "Utils.h"
#import "MacAlerts.h"
#import "CreateFormatAndSetCredentialsWizard.h"
#import "WindowController.h"
#import "Settings.h"
#import "AppDelegate.h"
#import "NSArray+Extensions.h"
#import "NodeDetailsViewController.h"
#import "BiometricIdHelper.h"
#import "AutoFillManager.h"
#import "SampleItemsGenerator.h"
#import "DatabaseModelConfig.h"
#import "Serializator.h"
#import "MacUrlSchemes.h"
#import "MacSyncManager.h"
#import "WorkingCopyManager.h"
#import "NSDate+Extensions.h"
#import "DatabaseUnlocker.h"
#import "MBProgressHUD.h"
#import "Strongbox-Swift.h"
#import "ViewController.h"
#import "DatabasesManagerVC.h"

NSString* const kModelUpdateNotificationFullReload = @"kModelUpdateNotificationFullReload"; 

@interface Document ()

@property WindowController* windowController;
@property BOOL isPromptingAboutUnderlyingFileChange;

@end

@implementation Document

- (void)dealloc {
    NSLog(@"😎 Document DEALLOC...");
}

- (instancetype)init {
    self = [super init];
    
    if (self) {
        NSLog(@"✅ Document::init");
        

    }
    
    return self;
}



- (MacDatabasePreferences *)databaseMetadata {
    if ( self.viewModel ) {
        return self.viewModel.databaseMetadata;
    }
    else if ( self.fileURL ) {
        MacDatabasePreferences* ret = [MacDatabasePreferences fromUrl:self.fileURL];
        
        if ( ret == nil ) {
            NSLog(@"🔴 WARNWARN: NIL MacDatabasePreferences - None Found in Document::databaseMetadata for URL: [%@]", self.fileURL);
            ret = [MacDatabasePreferences addOrGet:self.fileURL]; 
        }
        else {
            
        }
        
        return ret;
    }
    else {
        NSLog(@"🔴 WARNWARN: NIL fileUrl in Document::databaseMetadata");
        return nil;
    }
}

+ (BOOL)autosavesInPlace {
    return Settings.sharedInstance.autoSave;
}

- (BOOL)canAsynchronouslyWriteToURL:(NSURL *)url ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)saveOperation {
    return YES;
}

+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)typeName {
    return YES;
}

- (void)makeWindowControllers {
    NSLog(@"makeWindowControllers -> viewModel = [%@]", self.viewModel);

    if ( ( !Settings.sharedInstance.nextGenUI ) ) {
        NSStoryboard* storyboard = [NSStoryboard storyboardWithName:@"Main" bundle:nil];
        
        self.windowController = [storyboard instantiateControllerWithIdentifier:@"Document Window Controller"];
    }
    else {
        self.windowController = [[NSStoryboard storyboardWithName:@"NextGen" bundle:nil] instantiateInitialController];
    }
    
    [self addWindowController:self.windowController];
    
    [self.windowController changeContentView]; 
    
    [self listenForNotifications];
}

- (void)listenForNotifications {
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(onDatabaseReloaded:)
                                               name:kDatabaseReloadedNotificationKey
                                             object:nil];
    
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(onLockStateChanged:)
                                               name:kDatabasesCollectionLockStateChangedNotification
                                             object:nil];
}

- (void)onLockStateChanged:(id)notification {
    NSString* databaseUuid = ((NSNotification*)notification).object;
    
    if ( ![databaseUuid isEqualToString:self.databaseMetadata.uuid] ) {
        return;
    }
    
    NSLog(@"✅ Document::onLockStateChanged");
    
    [self bindToLockState];
}

- (void)bindToLockState {
    NSLog(@"✅ Document::bindToLockState");

    Model* model = [DatabasesCollection.shared getUnlockedWithUuid:self.databaseMetadata.uuid];
    
    if ( !self.viewModel || self.viewModel.locked ) {
        if ( model ) {
            NSLog(@"✅ Document::bindToLockState => Newly Unlocked");

            _viewModel = [[ViewModel alloc] initUnlocked:self databaseUuid:self.databaseMetadata.uuid model:model];
            [self bindWindowControllerAfterLockStatusChange];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ 
                if ( !self.viewModel.locked ) {
                    [self.viewModel restartBackgroundAudit];
                }
            });
        }
    }
    else {
        if ( !model ) {
            NSLog(@"✅ Document::bindToLockState => Newly Locked");

            _viewModel = [[ViewModel alloc] initLocked:self databaseUuid:self.databaseMetadata.uuid];
            [self bindWindowControllerAfterLockStatusChange];
        }
    }
}

- (void)onDatabaseReloaded:(id)notification {
    NSString* databaseUuid = ((NSNotification*)notification).object;
    
    if ( [databaseUuid isEqualToString:self.databaseMetadata.uuid] ) {
        NSLog(@"Document::onDatabaseReloaded => Notifying views to fully reload");
        
        [self notifyFullModelReload];
    }
}




- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError *__autoreleasing  _Nullable *)outError {
    NSLog(@"Document::readFromURL [%@] at [%@]", self.databaseMetadata.nickName, url);

    if ( !self.viewModel ) { 
        _viewModel = [[ViewModel alloc] initLocked:self databaseUuid:self.databaseMetadata.uuid];
    }
    
    [self bindToLockState];
    
    return YES;
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper ofType:(NSString *)typeName error:(NSError * _Nullable __autoreleasing *)outError {
    NSLog(@"readFromFileWrapper");

    if ( fileWrapper.isDirectory ) { 
        if(outError != nil) {
            NSString* loc = NSLocalizedString(@"mac_strongbox_cant_open_file_wrappers", @"Strongbox cannot open File Wrappers, Directories or Compressed Packages like this. Please directly select a KeePass or Password Safe database file.");
            *outError = [Utils createNSError:loc errorCode:-1];
        }
        return NO;
    }
    
    return [super readFromFileWrapper:fileWrapper ofType:typeName error:outError];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    NSLog(@"🔴 WARNWARN: Document::readFromData called %ld - [%@]", data.length, typeName);
    return NO;
}




- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem {
    SEL theAction = [anItem action];


    
    if (theAction == @selector(saveDocument:)) {
        return !self.viewModel.locked && !self.viewModel.isEffectivelyReadOnly;
    }
    
    return [super validateUserInterfaceItem:anItem];
}

- (IBAction)saveDocument:(id)sender {
    NSLog(@"Document::saveDocument");

    if(self.viewModel.locked || self.viewModel.isEffectivelyReadOnly) {
        NSLog(@"🔴 WARNWARN: Document is Read-Only or Locked! How did you get here?");
        return;
    }

    [super saveDocument:sender];
}

- (void)saveToURL:(NSURL *)url
           ofType:(NSString *)typeName
 forSaveOperation:(NSSaveOperationType)saveOperation
completionHandler:(void (^)(NSError * _Nullable))completionHandler {
    NSLog(@"✅ saveToURL: %lu - [%@] - [%@]", (unsigned long)saveOperation, self.fileModificationDate.friendlyDateTimeStringBothPrecise, url);
    
    BOOL updateQueued = [DatabasesCollection.shared updateAndQueueSyncWithUuid:self.databaseMetadata.uuid allowInteractiveSync:YES];
    
    if ( !updateQueued ) {
        NSLog(@"🔴 Could not queue a save for this database. Is it read-only or locked?!");
        completionHandler([Utils createNSError:@"🔴 Could not queue a save for this database. Is it read-only or locked?!" errorCode:-1]);
    }
    else {
        if (saveOperation != NSSaveToOperation) {
            [self updateChangeCount:NSChangeCleared];
        }
                
        completionHandler(nil);
    }
}






- (void)encodeRestorableStateWithCoder:(NSCoder *) coder {

    [coder encodeObject:self.fileURL forKey:@"StrongboxNonFileRestorationStateURL"];
}

- (NSURL *)presentedItemURL {
    if ( ![self.fileURL.scheme isEqualToString:kStrongboxSyncManagedFileUrlScheme] ) {
        return [super presentedItemURL];
    }
    else {
        NSURL* foo = fileUrlFromManagedUrl(self.fileURL);
        
        [super presentedItemURL]; 
        
        
        return foo;
    }
}




- (void)notifyFullModelReload {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:kModelUpdateNotificationFullReload
                                                          object:self
                                                        userInfo:@{ }];
    });
}

- (void)notifyUpdatesDatabasesList {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:kDatabasesListViewForceRefreshNotification object:nil];
    });
}



- (BOOL)isNextGenEditsInProgress {
    if ( Settings.sharedInstance.nextGenUI ) {
        if ( [self.windowController.contentViewController isKindOfClass:NextGenSplitViewController.class] ) { 
            NextGenSplitViewController* vc = (NextGenSplitViewController*)self.windowController.contentViewController;
            return vc.editsInProgress;
        }
    }
    
    return NO;
}




- (void)close {
    
    
    
    [self closeAllWindows];
    
    if ( Settings.sharedInstance.lockDatabaseOnWindowClose ) {
        [DatabasesCollection.shared forceLockWithUuid:self.databaseMetadata.uuid];
    }
    
    self.databaseMetadata.userRequestOfflineOpenEphemeralFlagForDocument = NO; 
    
    [NSNotificationCenter.defaultCenter removeObserver:self];
    
    [super close];
}

- (void)initiateLockSequence {
    NSLog(@"✅ Document::initiateLockSequence called...");

    if( !self.viewModel && self.viewModel.locked ) {
        return;
    }
    
    BOOL isEditing = [self isNextGenEditsInProgress];

    NSLog(@"Document::initiateLockSequence called... isEditing = %hhd", isEditing);

    if ( isEditing ) {
        if (!Settings.sharedInstance.lockEvenIfEditing ) {
            NSLog(@"⚠️ NOT Locking because there is an edit in progress.");
            return;
        }
        else {
            NSLog(@"⚠️ Locking even though there is an edit in progress to to configuration.");
        }
    }
    
    if ( self.isDocumentEdited ) {
        NSLog(@"✅ Document::initiateLockSequence isDocumentEdited = [YES]");

        NSString* loc = NSLocalizedString(@"generic_locking_ellipsis", @"Locking...");
        
        [macOSSpinnerUI.sharedInstance show:loc viewController:self.windowController.contentViewController];
        
        [self saveDocumentWithDelegate:self didSaveSelector:@selector(onSaveBeforeLockingCompletion:) contextInfo:nil];
    }
    else {
        
        
        [self onSaveBeforeLockingCompletion:nil];
    }
}

- (void)closeAllWindows {
    NSLog(@"✅ Document::closeAllWindows");
    
    if ( !self.viewModel.locked ) {
        if ( Settings.sharedInstance.nextGenUI ) {
            if ( [self.windowController.contentViewController isKindOfClass:NextGenSplitViewController.class] ) { 
                
                
                
                NextGenSplitViewController* vc = (NextGenSplitViewController*)self.windowController.contentViewController;
                
                [vc onLockDoneKillAllWindows];
            }
        }
        else {
            ViewController* vc = (ViewController*)self.windowController.contentViewController;
            
            [vc closeAllDetailsWindows:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [vc stopObservingModelAndCleanup];
                });
            }];
        }
    }
}

- (IBAction)onSaveBeforeLockingCompletion:(id)sender {
    NSLog(@"Document::onSaveBeforeLockingCompletion called...");

    [macOSSpinnerUI.sharedInstance dismiss];
    
    if ( Settings.sharedInstance.nextGenUI ) {
        
        if ( [self.windowController.contentViewController isKindOfClass:NextGenSplitViewController.class] ) { 
            
            NextGenSplitViewController* vc = (NextGenSplitViewController*)self.windowController.contentViewController;
            
            
            [vc onLockDoneKillAllWindows];
        }
        
        [self forceLock];
    }
    else {
        ViewController* vc = (ViewController*)self.windowController.contentViewController;
        
        __weak Document* weakSelf = self;
        [vc closeAllDetailsWindows:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf forceLock];
                [vc stopObservingModelAndCleanup];
            });
        }];
    }
    
    
    
    if ( Settings.sharedInstance.clearClipboardEnabled ) {
        AppDelegate* appDelegate = (AppDelegate*)[NSApplication sharedApplication].delegate;
        [appDelegate clearClipboardWhereAppropriate];
    }
}

- (void)forceLock {
    NSLog(@"✅ Document::forceLock called");
    
    if( self.isDocumentEdited ) {
        NSLog(@"⚠️ Cannot lock document with edits!");
        return;
    }
    
    
    
    [self.undoManager removeAllActions];
    
    self.wasJustLocked = YES;
    
    [DatabasesCollection.shared forceLockWithUuid:self.databaseMetadata.uuid];
    
    _viewModel = [[ViewModel alloc] initLocked:self databaseUuid:self.databaseMetadata.uuid];
    [self bindWindowControllerAfterLockStatusChange];
}

- (void)bindWindowControllerAfterLockStatusChange {
    WindowController* wc = self.windowController;
    
    
    
    if ( NSThread.isMainThread ) {
        [wc changeContentView];
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [wc changeContentView];
        });
    }
}



- (void)onDatabaseChangedByExternalOther {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _onDatabaseChangedByExternalOther];
    });
}

- (void)_onDatabaseChangedByExternalOther {
    if(self.isPromptingAboutUnderlyingFileChange) {
        NSLog(@"Already in Use...");
        return;
    }
    
    self.isPromptingAboutUnderlyingFileChange = YES;
    
    if (self.viewModel && !self.viewModel.locked) {
        NSLog(@"ViewController::onDatabaseChangedByExternalOther - Reloading...");
        
        if(!self.viewModel.document.isDocumentEdited) { 
            if( !self.databaseMetadata.autoReloadAfterExternalChanges ) {
                NSString* loc = NSLocalizedString(@"mac_db_changed_externally_reload_yes_or_no", @"The database has been changed by another application, would you like to reload this latest version and automatically unlock?");

                [MacAlerts yesNo:loc
                          window:self.windowController.window
                      completion:^(BOOL yesNo) {
                    if(yesNo) {
                        NSString* loc = NSLocalizedString(@"mac_db_reloading_after_external_changes_popup_notification", @"Reloading after external changes...");

                        [self showPopupChangeToastNotification:loc];
                        
                        [DatabasesCollection.shared syncWithUuid:self.databaseMetadata.uuid
                                                allowInteractive:YES
                                             suppressErrorAlerts:NO
                                                 ckfsForConflict:nil 
                                                      completion:nil];
                    }
                    
                    self.isPromptingAboutUnderlyingFileChange = NO;
                }];
                return;
            }
            else {
                NSString* loc = NSLocalizedString(@"mac_db_reloading_after_external_changes_popup_notification", @"Reloading after external changes...");

                [self showPopupChangeToastNotification:loc];

                [DatabasesCollection.shared syncWithUuid:self.databaseMetadata.uuid
                                        allowInteractive:YES
                                     suppressErrorAlerts:NO
                                         ckfsForConflict:nil 
                                              completion:nil];

                self.isPromptingAboutUnderlyingFileChange = NO;

                return;
            }
        }
        else {
            NSLog(@"Local Changes Present... ignore this, we can't auto reload...");
        }
    }
    else {
        NSLog(@"Ignoring File Change by Other Application because Database is locked/not set.");
    }
    
    self.isPromptingAboutUnderlyingFileChange = NO;
}



- (void)showPopupChangeToastNotification:(NSString*)message {
    [self showToastNotification:message error:NO];
}

- (void)showToastNotification:(NSString*)message error:(BOOL)error {
    if ( self.windowController.window.isMiniaturized ) {
        NSLog(@"Not Showing Popup Change notification because window is miniaturized");
        return;
    }

    [self showToastNotification:message error:error yOffset:150.f];
}

- (void)showToastNotification:(NSString*)message error:(BOOL)error yOffset:(CGFloat)yOffset {
    if ( !self.viewModel.showChangeNotifications ) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSColor *defaultColor = [NSColor colorWithDeviceRed:0.23 green:0.5 blue:0.82 alpha:0.60];
        NSColor *errorColor = [NSColor colorWithDeviceRed:1 green:0.55 blue:0.05 alpha:0.90];

        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.windowController.contentViewController.view animated:YES];
        hud.labelText = message;
        hud.color = error ? errorColor : defaultColor;
        hud.mode = MBProgressHUDModeText;
        hud.margin = 10.f;
        hud.yOffset = yOffset;
        hud.removeFromSuperViewOnHide = YES;
        hud.dismissible = YES;
        
        NSTimeInterval delay = error ? 3.0f : 0.5f;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [hud hide:YES];
        });
    });
}

@end
