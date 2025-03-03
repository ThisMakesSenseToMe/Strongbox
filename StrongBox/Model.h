//
//  SafeViewModel.h
//  StrongBox
//
//  Created by Mark McGuill on 20/06/2014.
//  Copyright (c) 2014 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OnboardingDatabaseChangeRequests.h"
#import "SearchScope.h"
#import "BrowseSortField.h"
#import "BrowseSortConfiguration.h"
#import "BrowseViewType.h"

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>

typedef UIViewController* VIEW_CONTROLLER_PTR;

#else

#import <Cocoa/Cocoa.h>

typedef NSViewController* VIEW_CONTROLLER_PTR;

#endif

#import "DatabaseModel.h"
#import "DatabaseAuditor.h"
#import "AsyncUpdateResult.h"
#import "CommonDatabasePreferences.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kSpecialSearchTermAllEntries;
extern NSString* const kSpecialSearchTermAuditEntries;
extern NSString* const kSpecialSearchTermTotpEntries;
extern NSString* const kSpecialSearchTermExpiredEntries;
extern NSString* const kSpecialSearchTermNearlyExpiredEntries;

typedef void (^AsyncUpdateCompletion)(AsyncUpdateResult *result);

extern NSString* const kAuditNodesChangedNotificationKey;
extern NSString* const kAuditProgressNotificationKey;
extern NSString* const kAuditCompletedNotificationKey;
extern NSString* const kProStatusChangedNotificationKey;
extern NSString* const kAppStoreSaleNotificationKey; 
extern NSString* const kCentralUpdateOtpUiNotification;
extern NSString* const kMasterDetailViewCloseNotification;
extern NSString* const kDatabaseViewPreferencesChangedNotificationKey;
extern NSString* const kWormholeAutoFillUpdateMessageId;
extern NSString* const kDatabaseReloadedNotificationKey;
extern NSString* const kTabsMayHaveChangedDueToModelEdit;
extern NSString* const kAsyncUpdateDone;
extern NSString* const kAsyncUpdateStarting;

@interface Model : NSObject

@property (nonatomic, readonly) NSString *databaseUuid;
@property (nonatomic, readonly, nonnull) METADATA_PTR metadata;
@property (readonly, strong, nonatomic, nonnull) DatabaseModel *database;   
@property (nonatomic, readonly) BOOL isReadOnly;
@property (readonly) BOOL isInOfflineMode;

@property (readonly) BOOL formatSupportsCustomIcons;
@property (readonly) BOOL formatSupportsTags;

@property (nonatomic, readonly, nonnull) NSArray<Node*> *allItems;
@property (nonatomic, readonly, nonnull) NSArray<Node*> *allEntries;

@property (nonatomic, nonnull) CompositeKeyFactors *ckfs;



- (instancetype)init NS_UNAVAILABLE;

- (instancetype _Nullable )initWithDatabase:(DatabaseModel *_Nonnull)passwordDatabase
                                   metaData:(METADATA_PTR _Nonnull)metaData
                             forcedReadOnly:(BOOL)forcedReadOnly
                                 isAutoFill:(BOOL)isAutoFill;

- (instancetype _Nullable )initWithDatabase:(DatabaseModel *_Nonnull)passwordDatabase
                                   metaData:(METADATA_PTR _Nonnull)metaData
                             forcedReadOnly:(BOOL)forcedReadOnly
                                 isAutoFill:(BOOL)isAutoFill
                                offlineMode:(BOOL)offlineMode; 

#if TARGET_OS_IPHONE

- (instancetype)initAsDuressDummy:(BOOL)isNativeAutoFillAppExtensionOpen
                 templateMetaData:(METADATA_PTR)templateMetaData;

#endif

- (void)reloadDatabaseFromLocalWorkingCopy:(VIEW_CONTROLLER_PTR)viewController 
                                completion:(void(^_Nullable)(BOOL success))completion;

- (void)stopAudit;
- (void)restartBackgroundAudit;
- (void)stopAndClearAuditor;

- (Node*_Nullable)getItemById:(NSUUID*)uuid;
- (NSArray<Node*>*)getItemsById:(NSArray<NSUUID*>*)ids;

@property (readonly) AuditState auditState;
@property (readonly, nullable) NSNumber* auditIssueCount;
@property (readonly) NSUInteger auditIssueNodeCount;
@property (readonly) NSUInteger auditHibpErrorCount;

- (NSSet<NSNumber*>*)getQuickAuditFlagsForNode:(NSUUID*)item;
- (BOOL)isFlaggedByAudit:(NSUUID*)item;
- (NSString*)getQuickAuditSummaryForNode:(NSUUID*)item;
- (NSString*)getQuickAuditVeryBriefSummaryForNode:(NSUUID*)item;
- (NSArray<NSString *>*)getQuickAuditAllIssuesVeryBriefSummaryForNode:(NSUUID *)item;
- (NSArray<NSString *>*)getQuickAuditAllIssuesSummaryForNode:(NSUUID *)item;

- (void)replaceEntireUnderlyingDatabaseWith:(DatabaseModel*)newDatabase; 

@property (readonly, nullable) DatabaseAuditReport* auditReport;

- (NSSet<Node*>*)getSimilarPasswordNodeSet:(NSUUID*)node;
- (NSSet<Node*>*)getDuplicatedPasswordNodeSet:(NSUUID*)node;

- (void)excludeFromAudit:(Node*)node exclude:(BOOL)exclude;
- (BOOL)isExcludedFromAudit:(NSUUID*)item;
- (NSArray<Node*>*)getExcludedAuditItems;
- (void)oneTimeHibpCheck:(NSString*)password completion:(void(^)(BOOL pwned, NSError* error))completion;

- (void)closeAndCleanup;



- (NSInteger)reorderItem:(NSUUID*)nodeId idx:(NSInteger)idx;
- (NSInteger)reorderChildFrom:(NSUInteger)from to:(NSInteger)to parentGroup:(Node*)parentGroup;

- (Node*_Nullable)addNewGroup:(Node *_Nonnull)parentGroup title:(NSString*)title;

- (BOOL)validateAddChildren:(NSArray<Node *>*)items destination:(Node *)destination;

- (BOOL)addChildren:(NSArray<Node *>*)items destination:(Node *)destination;

- (void)deleteItems:(const NSArray<Node *> *)items;
- (BOOL)recycleItems:(const NSArray<Node *> *)items;

- (BOOL)canRecycle:(NSUUID*_Nonnull)itemId;

- (BOOL)isFavourite:(NSUUID*)itemId;
- (BOOL)toggleFavourite:(NSUUID*)itemId;
@property (readonly) NSArray<Node*>* favourites;

- (BOOL)launchUrl:(Node*)item;
- (BOOL)launchUrlString:(NSString*)urlString;


-(void)encrypt:(VIEW_CONTROLLER_PTR)viewController completion:(void (^)(BOOL userCancelled, NSString*_Nullable file, NSString*_Nullable debugXml, NSError*_Nullable error))completion;

- (NSString *_Nonnull)generatePassword;



- (void)disableAndClearAutoFill;
- (void)enableAutoFill;



- (void)update:(VIEW_CONTROLLER_PTR)viewController handler:(void(^)(BOOL userCancelled, BOOL localWasChanged, NSError * _Nullable error))handler;



@property (nullable) AsyncUpdateResult* lastAsyncUpdateResult;
@property (readonly) BOOL isRunningAsyncUpdate;

- (BOOL)asyncUpdateAndSync; 
- (BOOL)asyncUpdate:(AsyncUpdateCompletion _Nullable)completion;

- (void)clearAsyncUpdateState;



@property BOOL isDuressDummyDatabase; 

@property (nullable) OnboardingDatabaseChangeRequests* onboardingDatabaseChangeRequests;



@property (nonatomic, readonly) DatabaseFormat originalFormat;
- (BOOL)isDereferenceableText:(NSString*)text;
- (NSString*)dereference:(NSString*)text node:(Node*)node;



- (NSArray<Node*>*)entriesWithTag:(NSString*)tag;

- (NSArray<Node*>*)search:(NSString *)searchText
                    scope:(SearchScope)scope
              dereference:(BOOL)dereference
    includeKeePass1Backup:(BOOL)includeKeePass1Backup
        includeRecycleBin:(BOOL)includeRecycleBin
           includeExpired:(BOOL)includeExpired
            includeGroups:(BOOL)includeGroups
          browseSortField:(BrowseSortField)browseSortField
               descending:(BOOL)descending
        foldersSeparately:(BOOL)foldersSeparately;

- (NSArray<Node*>*)search:(NSString *)searchText
                    scope:(SearchScope)scope
              dereference:(BOOL)dereference
    includeKeePass1Backup:(BOOL)includeKeePass1Backup
        includeRecycleBin:(BOOL)includeRecycleBin
           includeExpired:(BOOL)includeExpired
            includeGroups:(BOOL)includeGroups
                 trueRoot:(BOOL)trueRoot
          browseSortField:(BrowseSortField)browseSortField
               descending:(BOOL)descending
        foldersSeparately:(BOOL)foldersSeparately;

- (NSArray<Node*>*)filterAndSortForBrowse:(NSMutableArray<Node*>*)nodes
                    includeKeePass1Backup:(BOOL)includeKeePass1Backup
                        includeRecycleBin:(BOOL)includeRecycleBin
                           includeExpired:(BOOL)includeExpired
                            includeGroups:(BOOL)includeGroups
                          browseSortField:(BrowseSortField)browseSortField
                               descending:(BOOL)descending
                        foldersSeparately:(BOOL)foldersSeparately;

- (NSArray<Node*>*)sortItemsForBrowse:(NSArray<Node*>*)items
                      browseSortField:(BrowseSortField)browseSortField
                           descending:(BOOL)descending
                    foldersSeparately:(BOOL)foldersSeparately;

- (NSComparisonResult)compareNodesForSort:(Node*)node1
                                    node2:(Node*)node2
                                    field:(BrowseSortField)field
                               descending:(BOOL)descending
                        foldersSeparately:(BOOL)foldersSeparately;

- (void)rebuildFastMaps; 

#ifndef IS_APP_EXTENSION 

- (NSArray<Node *> *)getAutoFillMatchingNodesForUrl:(NSString *)urlString;
- (void)rebuildAutoFillDomainNodeMap;

#endif

#if TARGET_OS_IPHONE

- (BrowseSortConfiguration*)getDefaultSortConfiguration;
- (BrowseSortConfiguration*)getSortConfigurationForViewType:(BrowseViewType)viewType;
- (void)setSortConfigurationForViewType:(BrowseViewType)viewType configuration:(BrowseSortConfiguration*)configuration;

#endif

@end

NS_ASSUME_NONNULL_END
