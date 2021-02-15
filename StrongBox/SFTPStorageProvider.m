//
//  SFTPStorageProvider.m
//  Strongbox
//
//  Created by Mark on 11/12/2018.
//  Copyright © 2014-2021 Mark McGuill. All rights reserved.
//

#import "SFTPStorageProvider.h"
#import "Utils.h"
#import "NMSSH.h"
#import "Settings.h"
#import "NSArray+Extensions.h"
#import "SFTPProviderData.h"
#import "Constants.h"
#import "NSDate+Extensions.h"

#if TARGET_OS_IPHONE

#import "SFTPSessionConfigurationViewController.h"
#import "SVProgressHUD.h"
#import "Alerts.h"

#else

#import "SFTPConfigurationVC.h"
#import "MacAlerts.h"
#import "MacUrlSchemes.h"

#endif


@interface SFTPStorageProvider ()

@property NMSFTP* maintainedSessionForListing;
@property SFTPSessionConfiguration* maintainedConfigurationForFastListing;

@end

@implementation SFTPStorageProvider

+ (instancetype)sharedInstance {
    static SFTPStorageProvider *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SFTPStorageProvider alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if(self = [super init]) {
        _storageId = kSFTP;
        _providesIcons = NO;
        _browsableNew = YES;
        _browsableExisting = YES;
        _rootFolderOnly = NO;
        _defaultForImmediatelyOfferOfflineCache = NO; 
        _supportsConcurrentRequests = NO; 
    }
    
    return self;
}

- (void)dismissProgressSpinner {
#if TARGET_OS_IPHONE
    dispatch_async(dispatch_get_main_queue(), ^{
        [SVProgressHUD dismiss];
    });
#else
    
#endif
}

- (void)showProgressSpinner:(NSString*)message {
#if TARGET_OS_IPHONE
    dispatch_async(dispatch_get_main_queue(), ^{
        [SVProgressHUD showWithStatus:message]; 
    });
#else
    
#endif
}

- (void)create:(NSString *)nickName
     extension:(NSString *)extension
          data:(NSData *)data
  parentFolder:(NSObject *)parentFolder
viewController:(VIEW_CONTROLLER_PTR )viewController
    completion:(void (^)(METADATA_PTR , const NSError *))completion {
    if(self.maintainSessionForListing && self.maintainedSessionForListing) { 
        [self createWithSession:nickName extension:extension data:data
                   parentFolder:parentFolder sftp:self.maintainedSessionForListing
                  configuration:self.maintainedConfigurationForFastListing completion:completion];
    }
    else {
        [self connectAndAuthenticate:nil
                      viewController:viewController
                          completion:^(BOOL userCancelled, NMSFTP *sftp, SFTPSessionConfiguration *configuration, NSError *error) {
            if(userCancelled || sftp == nil || error) {
                completion(nil, error);
                return;
            }
            
            [self createWithSession:nickName extension:extension data:data parentFolder:parentFolder sftp:sftp configuration:configuration completion:completion];
        }];
    }
}

-(void)createWithSession:(NSString *)nickName
               extension:(NSString *)extension
                    data:(NSData *)data
            parentFolder:(NSObject *)parentFolder
                    sftp:(NMSFTP*)sftp
           configuration:(SFTPSessionConfiguration*)configuration
              completion:(void (^)(METADATA_PTR , NSError *))completion {
    NSString *desiredFilename = [NSString stringWithFormat:@"%@.%@", nickName, extension];
    NSString *dir = [self getDirectoryFromParentFolderObject:parentFolder sessionConfig:configuration];
    NSString *path = [NSString pathWithComponents:@[dir, desiredFilename]];

    if(![sftp writeContents:data toFileAtPath:path progress:nil]) {
        NSError* error = [Utils createNSError:NSLocalizedString(@"sftp_provider_could_not_create", @"Could not create file") errorCode:-3];
        completion(nil, error);
        return;
    }
    
    SFTPProviderData* providerData = makeProviderData(path, configuration);
    METADATA_PTR metadata = [self getSafeMetaData:nickName providerData:providerData];

    [sftp disconnect];

    completion(metadata, nil);
}

- (void)list:(NSObject *)parentFolder
viewController:(VIEW_CONTROLLER_PTR )viewController
  completion:(void (^)(BOOL, NSArray<StorageBrowserItem *> *, const NSError *))completion {
    if(self.maintainSessionForListing && self.maintainedSessionForListing) {
        [self listWithSftpSession:self.maintainedSessionForListing
                     parentFolder:parentFolder
                    configuration:self.maintainedConfigurationForFastListing
                       completion:completion];
    }
    else {
        [self connectAndAuthenticate:nil
                      viewController:viewController
                          completion:^(BOOL userCancelled, NMSFTP *sftp, SFTPSessionConfiguration *configuration, NSError *error) {
            if(userCancelled || sftp == nil || error) {
                completion(userCancelled, nil, error);
                return;
            }
                              
            if(self.maintainSessionForListing) {
                self.maintainedSessionForListing = sftp;
                self.maintainedConfigurationForFastListing = configuration;
            }
                              
            [self listWithSftpSession:sftp parentFolder:parentFolder configuration:configuration completion:completion];
                              
            if(!self.maintainSessionForListing) {
                [sftp disconnect];
            }
        }];
    }
}

- (void)listWithSftpSession:(NMSFTP*)sftp
               parentFolder:(NSObject *)parentFolder
              configuration:(SFTPSessionConfiguration *)configuration
                 completion:(void (^)(BOOL, NSArray<StorageBrowserItem *> *, NSError *))completion {
    [self showProgressSpinner:NSLocalizedString(@"storage_provider_status_authenticating_listing", @"Listing...")];
    
    NSString * dir = [self getDirectoryFromParentFolderObject:parentFolder sessionConfig:configuration];
    
    NSArray<NMSFTPFile*>* files = [sftp contentsOfDirectoryAtPath:dir];
    
    [self dismissProgressSpinner];
    
    if (files == nil) {
        completion(NO, nil, sftp.session.lastError); 
    }
    else {
        NSArray<StorageBrowserItem*>* browserItems = [files map:^id _Nonnull(NMSFTPFile * _Nonnull obj, NSUInteger idx) {
            NSString* name = obj.isDirectory && obj.filename.length > 1 ? [obj.filename substringToIndex:obj.filename.length-1] : obj.filename;
            BOOL folder = obj.isDirectory;
            NSString* path = [NSString pathWithComponents:@[dir, name]];
            id providerData = makeProviderData(path, configuration);
            
            return [StorageBrowserItem itemWithName:name identifier:path folder:folder providerData:providerData];
        }];
        
        completion(NO, browserItems, nil);
    }
}

- (void)pushDatabase:(METADATA_PTR )safeMetaData
       interactiveVC:(VIEW_CONTROLLER_PTR )viewController
                data:(NSData *)data
          completion:(StorageProviderUpdateCompletionBlock)completion {
    SFTPProviderData* providerData = [self getProviderDataFromMetaData:safeMetaData];
    
    [self connectAndAuthenticate:providerData.sFtpConfiguration
                  viewController:nil
                      completion:^(BOOL userCancelled, NMSFTP *sftp, SFTPSessionConfiguration *configuration, NSError *error) {
        if(sftp == nil || error) {
            completion(kUpdateResultError, nil, error);
            return;
        }
    
        if (viewController) {
            [self showProgressSpinner:NSLocalizedString(@"storage_provider_status_syncing", @"Syncing...")];
        }

        if(![sftp writeContents:data toFileAtPath:providerData.filePath progress:nil]) {
            if (viewController) {
                [self dismissProgressSpinner];
            }

            error = [Utils createNSError:NSLocalizedString(@"sftp_provider_could_not_update", @"Could not update file") errorCode:-3];
            completion(kUpdateResultError, nil, error);
        }
        else {
            NMSFTPFile* attr = [sftp infoForFileAtPath:providerData.filePath];
            if(!attr) {
                error = [Utils createNSError:NSLocalizedString(@"sftp_provider_could_not_read", @"Could not read file") errorCode:-3];
                completion(kUpdateResultError, nil, error);
            }

            if (viewController) {
                [self dismissProgressSpinner];
            }
            
            completion(kUpdateResultSuccess, attr.modificationDate, nil);
        }
        
        [sftp disconnect];
    }];
}



- (void)delete:(METADATA_PTR )safeMetaData completion:(void (^)(const NSError *))completion {
    
}

- (void)loadIcon:(NSObject *)providerData viewController:(VIEW_CONTROLLER_PTR )viewController completion:(void (^)(IMAGE_TYPE_PTR))completionHandler {
    
}




- (SFTPProviderData*)getProviderDataFromMetaData:(METADATA_PTR )metaData {
#if TARGET_OS_IPHONE
    NSString* json = metaData.fileIdentifier;
#else
    NSString* json = metaData.storageInfo;
#endif

    NSError* error;
    NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]  options:kNilOptions error:&error];
    
    SFTPProviderData* foo = [SFTPProviderData fromSerializationDictionary:dictionary];
    
    return foo;
}

- (METADATA_PTR )getSafeMetaData:(NSString *)nickName providerData:(NSObject *)providerData {
    SFTPProviderData* foo = (SFTPProviderData*)providerData;
    
    NSError* error;
    NSData* data = [NSJSONSerialization dataWithJSONObject:[foo serializationDictionary] options:0 error:&error];
    
    if(error) {
        NSLog(@"%@", error);
        return nil;
    }

    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

#if TARGET_OS_IPHONE
    return [[SafeMetaData alloc] initWithNickName:nickName
                                  storageProvider:self.storageId
                                         fileName:[foo.filePath lastPathComponent]
                                   fileIdentifier:json];
#else
    NSURLComponents* components = [[NSURLComponents alloc] init];
    components.scheme = kStrongboxSFTPUrlScheme;
    components.host = foo.sFtpConfiguration.host;
    components.path = foo.filePath;
    
    return [[DatabaseMetadata alloc] initWithNickName:nickName storageProvider:self.storageId fileUrl:components.URL storageInfo:json];
#endif
}

- (void)pullDatabase:(METADATA_PTR)safeMetaData
         interactiveVC:(VIEW_CONTROLLER_PTR )viewController
                options:(StorageProviderReadOptions *)options
             completion:(StorageProviderReadCompletionBlock)completion {
    SFTPProviderData* providerData = [self getProviderDataFromMetaData:safeMetaData];
    [self readWithProviderData:providerData viewController:viewController options:options completion:completion];
}

- (void)readWithProviderData:(NSObject *)providerData
              viewController:(VIEW_CONTROLLER_PTR )viewController
                     options:(StorageProviderReadOptions *)options
                  completion:(StorageProviderReadCompletionBlock)completionHandler {
    SFTPProviderData* foo = (SFTPProviderData*)providerData;
    
    [self connectAndAuthenticate:foo.sFtpConfiguration
                  viewController:viewController
                      completion:^(BOOL userCancelled, NMSFTP *sftp, SFTPSessionConfiguration *configuration, NSError *error) {
        if(sftp == nil || error) {
            completionHandler(kReadResultError, nil, nil, error);
            return;
        }
        
        if (viewController) {
            [self showProgressSpinner:NSLocalizedString(@"storage_provider_status_reading", @"A storage provider is in the process of reading. This is the status displayed on the progress dialog. In english:  Reading...")];
        }
        
        NMSFTPFile* attr = [sftp infoForFileAtPath:foo.filePath];
        if(!attr) {
            error = [Utils createNSError:NSLocalizedString(@"sftp_provider_could_not_read", @"Could not read file") errorCode:-3];
            completionHandler(kReadResultError, nil, nil, error);
            return;
        }
        
        if (options.onlyIfModifiedDifferentFrom && [options.onlyIfModifiedDifferentFrom isEqualToDateWithinEpsilon:attr.modificationDate]) {
            if (viewController) {
                [self dismissProgressSpinner];
            }

            completionHandler(kReadResultModifiedIsSameAsLocal, nil, nil, error);
            return;
        }

        NSData* data = [sftp contentsAtPath:foo.filePath];
        
        if (viewController) {
            [self dismissProgressSpinner];
        }
     
        if(!data) {
            error = [Utils createNSError:NSLocalizedString(@"sftp_provider_could_not_read", @"Could not read file") errorCode:-3];
            completionHandler(kReadResultError, nil, nil, error);
            return;
        }
        
        [sftp disconnect];
        
        completionHandler(kReadResultSuccess, data, attr.modificationDate, nil);
    }];
}

- (NSString *)getDirectoryFromParentFolderObject:(NSObject *)parentFolder sessionConfig:(SFTPSessionConfiguration*)sessionConfig {
    SFTPProviderData* parent = (SFTPProviderData*)parentFolder;

    NSString* dir = parent ? parent.filePath : (sessionConfig != nil && sessionConfig.initialDirectory.length ? sessionConfig.initialDirectory : @"/");

    return dir;
}

#if TARGET_OS_IPHONE
- (void)iOSGetConfiguration:(VIEW_CONTROLLER_PTR)viewController
                 completion:(void (^)(BOOL userCancelled, NMSFTP* sftp, SFTPSessionConfiguration* configuration, NSError* error))completion {
    SFTPSessionConfigurationViewController *vc = [[SFTPSessionConfigurationViewController alloc] init];
    __weak SFTPSessionConfigurationViewController* weakRef = vc;
    vc.onDone = ^(BOOL success) {
        if(success) {
            NSError* error;
            NMSFTP* sftp = [self connectAndAuthenticateWithSessionConfiguration:weakRef.configuration viewController:viewController error:&error];
            
            if (sftp && !error) {
                [viewController dismissViewControllerAnimated:YES completion:^{
                    completion(NO, sftp, weakRef.configuration, error);
                }];
            }
            else {
                [Alerts error:weakRef error:error];
            }
        }
        else {
            [viewController dismissViewControllerAnimated:YES completion:^{
                completion(YES, nil, nil, nil);
            }];
        }
    };
    
    vc.modalPresentationStyle = UIModalPresentationFormSheet;
    [viewController presentViewController:vc animated:YES completion:nil];
}
#else
- (void)macOSGetConfiguration:(VIEW_CONTROLLER_PTR)viewController
                   completion:(void (^)(BOOL userCancelled, NMSFTP* sftp, SFTPSessionConfiguration* configuration, NSError* error))completion {
    SFTPConfigurationVC* configVC = [SFTPConfigurationVC newConfigurationVC];
    
    configVC.onDone = ^(BOOL success, SFTPSessionConfiguration * _Nonnull configuration) {
        if (success) {


            NSError* error;
            NMSFTP* sftp = [self connectAndAuthenticateWithSessionConfiguration:configuration viewController:viewController error:&error];

            if (sftp && !error) {
                completion(NO, sftp, configuration, error);
            }
            else {
                NSLog(@"SFTP error: %@", error);
                completion(NO, nil, nil, error);
            }
        }
        else {
            completion(YES, nil, nil, nil);
        }
    };

    [viewController presentViewControllerAsSheet:configVC];
}

#endif

- (void)connectAndAuthenticate:(SFTPSessionConfiguration*)sessionConfiguration
                viewController:(VIEW_CONTROLLER_PTR)viewController
                    completion:(void (^)(BOOL userCancelled, NMSFTP* sftp, SFTPSessionConfiguration* configuration, NSError* error))completion {
    
    
    
    
    if(sessionConfiguration == nil) {
        if(self.unitTestingSessionConfiguration != nil) {
            sessionConfiguration = self.unitTestingSessionConfiguration;
        }
        else {
#if TARGET_OS_IPHONE
            [self iOSGetConfiguration:viewController completion:completion];
#else
            dispatch_async(dispatch_get_main_queue(), ^{
                [self macOSGetConfiguration:viewController completion:completion];
            });
#endif
            return;
        }
    }
    
    NSError* error;
    NMSFTP* sftp = [self connectAndAuthenticateWithSessionConfiguration:sessionConfiguration viewController:viewController error:&error];
    self.unitTestingSessionConfiguration = sessionConfiguration;
    completion(NO, sftp, sessionConfiguration, error);
}

- (NMSFTP*)connectAndAuthenticateWithSessionConfiguration:(SFTPSessionConfiguration*)sessionConfiguration
                                           viewController:viewController
                                                    error:(NSError**)error {
    NSLog(@"Connecting to %@", sessionConfiguration.host);
    
    if (viewController) {
        [self showProgressSpinner:NSLocalizedString(@"storage_provider_status_authenticating_connecting", @"Connecting...")];
    }
    
    NMSSHSession *session = [NMSSHSession connectToHost:sessionConfiguration.host
                                           withUsername:sessionConfiguration.username];

    if (viewController) {
        [self dismissProgressSpinner];
    }
    
    if (session.isConnected) {
        if (viewController) {
            [self showProgressSpinner:NSLocalizedString(@"storage_provider_status_authenticating", @"Authenticating...")];
        }
        
        NSLog(@"Supported Authentication Methods by Server: [%@]", session.supportedAuthenticationMethods);
        
        if(sessionConfiguration.authenticationMode == kPrivateKey) {
            [session authenticateByInMemoryPublicKey:sessionConfiguration.publicKey
                                          privateKey:sessionConfiguration.privateKey
                                         andPassword:sessionConfiguration.password];
        }
        else {
            [session authenticateByPassword:sessionConfiguration.password];
        }

        if (viewController) {
            [self dismissProgressSpinner];
        }

        if (!session.isAuthorized) {
            if(error) {
                *error = [Utils createNSError:[NSString stringWithFormat:NSLocalizedString(@"sftp_provider_auth_failed_fmt", @"Authentication Failed for [user: %@]"), sessionConfiguration.username] errorCode:-2];
            }
            return nil;
        }
    }
    else {
        if(error) {
            *error = [Utils createNSError:[NSString stringWithFormat:NSLocalizedString(@"sftp_provider_connect_failed_fmt", @"Could not connect to host: %@ [user: %@]"),
                                           sessionConfiguration.host, sessionConfiguration.username] errorCode:-1];
        }
        return nil;
    }
    
    NMSFTP *sftp = [NMSFTP connectWithSession:session];
    
    return sftp;
}

static SFTPProviderData* makeProviderData(NSString* path, SFTPSessionConfiguration* sftpConfiguration) {
    SFTPProviderData *providerData = [[SFTPProviderData alloc] init];
    
    providerData.filePath = path;
    providerData.sFtpConfiguration = sftpConfiguration;
    
    return providerData;
}

@end

