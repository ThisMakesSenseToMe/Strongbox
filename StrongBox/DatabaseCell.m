//
//  DatabaseCell.m
//  Strongbox
//
//  Created by Mark on 30/07/2019.
//  Copyright © 2019 Mark McGuill. All rights reserved.
//

#import "DatabaseCell.h"
#import "SafeMetaData.h"
#import "DatabaseCellSubtitleField.h"
#import "SharedAppAndAutoFillSettings.h"
#import "SafeStorageProviderFactory.h"
#import "Utils.h"
#import "NSDate+Extensions.h"
#import "SyncManager.h"
#import "LocalDeviceStorageProvider.h"

NSString* const kDatabaseCell = @"DatabaseCell";

@interface DatabaseCell ()

@property (weak, nonatomic) IBOutlet UIImageView *providerIcon;
@property (weak, nonatomic) IBOutlet UILabel *name;
@property (weak, nonatomic) IBOutlet UILabel *subtitle1;
@property (weak, nonatomic) IBOutlet UILabel *subtitle2;
@property (weak, nonatomic) IBOutlet UILabel *topSubtitle;
@property (weak, nonatomic) IBOutlet UIView *bottomRow;

@property (weak, nonatomic) IBOutlet UIImageView *status1;
@property (weak, nonatomic) IBOutlet UIImageView *status2;
@property (weak, nonatomic) IBOutlet UIImageView *status3;
@property (weak, nonatomic) IBOutlet UIImageView *status4;
@property (weak, nonatomic) IBOutlet UIImageView *status5;

@end

@implementation DatabaseCell

- (void)prepareForReuse {
    [super prepareForReuse];
    
//    NSLog(@"XXXXXXXXXXXXXX - prepareForReuse [%@]", self.name.text);

    self.bottomRow.hidden = NO;
    self.subtitle1.hidden = NO;
    self.subtitle2.hidden = NO;
    self.topSubtitle.hidden = NO;
    
    self.status1.image = nil;
    self.status1.hidden = YES;
    self.status2.image = nil;
    self.status2.hidden = YES;
    self.status3.image = nil;
    self.status3.hidden = YES;
    self.status4.image = nil;
    self.status4.hidden = YES;
    self.status5.image = nil;
    self.status5.hidden = YES;
}

- (void)setEnabled:(BOOL)enabled {
    self.imageView.userInteractionEnabled = enabled;
    self.userInteractionEnabled = enabled;
    self.textLabel.enabled = enabled;
    self.detailTextLabel.enabled = enabled;
    self.name.enabled = enabled;
    self.subtitle1.enabled = enabled;
    self.subtitle2.enabled = enabled;
    self.providerIcon.userInteractionEnabled = enabled;
    self.topSubtitle.enabled = enabled;
    
    self.status1.userInteractionEnabled = enabled;
    self.status2.userInteractionEnabled = enabled;
    self.status3.userInteractionEnabled = enabled;
    self.status4.userInteractionEnabled = enabled;
    self.status5.userInteractionEnabled = enabled;
}

- (void)set:(NSString*)name
topSubtitle:(NSString*)topSubtitle
  subtitle1:(NSString*)subtitle1
  subtitle2:(NSString*)subtitle2
providerIcon:(UIImage*)providerIcon
statusImages:(NSArray<UIImage*>*)statusImages
rotateLastImage:(BOOL)rotateLastImage
      tints:(nonnull NSArray *)tints
   disabled:(BOOL)disabled {
//    NSLog(@"XXXXXXXXXXXXXX - SET Database Cell for db [%@]", name);
    
    self.name.text = name;

    self.providerIcon.image = providerIcon;
    self.providerIcon.hidden = providerIcon == nil;

    self.topSubtitle.text = topSubtitle ? topSubtitle : @"";
    self.subtitle1.text = subtitle1 ? subtitle1 : @"";
    self.subtitle2.text = subtitle2 ? subtitle2 : @"";
    
    self.subtitle1.hidden = subtitle1 == nil;
    self.subtitle2.hidden = subtitle2 == nil;
    self.topSubtitle.hidden = topSubtitle == nil;
    
    self.bottomRow.hidden = subtitle1 == nil && subtitle2 == nil;

    NSArray<UIImageView*>* statusImageControls = @[self.status1, self.status2, self.status3, self.status4, self.status5];
    
    for (int i = 0; i < statusImageControls.count; i++) {
        UIImage* image = i < statusImages.count ? statusImages[i] : nil;
        
        statusImageControls[i].image = image;
        statusImageControls[i].hidden = image == nil;
        statusImageControls[i].tintColor = (image != nil && tints && (tints[i] != NSNull.null)) ? tints[i] : nil;
        
        [self runSpinAnimationOnView:statusImageControls[i] doIt:(i == statusImages.count - 1 && rotateLastImage) duration:1.0 rotations:1.0 repeat:1024 * 1024];
    }
    
    [self setEnabled:!disabled];
}

- (void)runSpinAnimationOnView:(UIView*)view doIt:(BOOL)doIt duration:(CGFloat)duration rotations:(CGFloat)rotations repeat:(float)repeat {
//    NSLog(@"XXXXXXXXXXXXXX - runSpinAnimationOnView for db [%@]-[%@]", self.name.text, doIt ? @"YUP" : @"Nope");

    [view.layer removeAllAnimations];
    
    if (doIt) {
        CABasicAnimation* rotationAnimation;
        rotationAnimation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        rotationAnimation.toValue = [NSNumber numberWithFloat: M_PI * 2.0 /* full rotation*/ * rotations * duration ];
        rotationAnimation.duration = duration;
        rotationAnimation.cumulative = YES;
        rotationAnimation.repeatCount = repeat ? HUGE_VALF : 0;
        [rotationAnimation setRemovedOnCompletion:NO]; // Required or animation stops if the app deactivates or another view controller is pushed on the nav stack :(
        
        [view.layer addAnimation:rotationAnimation forKey:@"rotationAnimation"];
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)populateCell:(SafeMetaData*)database {
    [self populateCell:database disabled:NO autoFill:NO];
}

- (void)populateCell:(SafeMetaData *)database disabled:(BOOL)disabled autoFill:(BOOL)autoFill {
    SyncOperationState syncState = autoFill ? kSyncOperationStateInitial : [SyncManager.sharedInstance getSyncStatus:database].state;
    
    NSArray* tints;
    NSArray<UIImage*>* statusImages =  [self getStatusImages:database syncState:syncState tints:&tints];
        
    NSString* topSubtitle = [self getDatabaseCellSubtitleField:database field:SharedAppAndAutoFillSettings.sharedInstance.databaseCellTopSubtitle];
    NSString* subtitle1 = [self getDatabaseCellSubtitleField:database field:SharedAppAndAutoFillSettings.sharedInstance.databaseCellSubtitle1];
    NSString* subtitle2 = [self getDatabaseCellSubtitleField:database field:SharedAppAndAutoFillSettings.sharedInstance.databaseCellSubtitle2];
    
    NSString* databaseIconName = [SafeStorageProviderFactory getIcon:database];
    UIImage* databaseIcon = SharedAppAndAutoFillSettings.sharedInstance.showDatabaseIcon ? [UIImage imageNamed:databaseIconName] : nil;

    if (disabled) {
        databaseIcon = SharedAppAndAutoFillSettings.sharedInstance.showDatabaseIcon ? [UIImage imageNamed:@"cancel_32"] : nil;
        
        if (autoFill) {
            subtitle2 = database.autoFillEnabled ?
                NSLocalizedString(@"autofill_vc_item_subtitle_local_copy_unavailable", @"Local Copy Unavailable") :
                NSLocalizedString(@"autofill_vc_item_subtitle_disabled", @"AutoFill Disabled");
        }
    }
    
    [self set:database.nickName
  topSubtitle:topSubtitle
    subtitle1:subtitle1
    subtitle2:subtitle2
 providerIcon:databaseIcon
 statusImages:statusImages
     rotateLastImage:syncState == kSyncOperationStateInProgress
        tints:tints
     disabled:disabled];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray<UIImage*>*)getStatusImages:(SafeMetaData*)database syncState:(SyncOperationState)syncState tints:(NSArray**)tints {
    NSMutableArray<UIImage*> *ret = NSMutableArray.array;
    NSMutableArray *tnts = NSMutableArray.array;

    if(database.hasUnresolvedConflicts) {
        [ret addObject:[UIImage imageNamed:@"error"]];
        [tnts addObject:NSNull.null];
    }
    
    if (SharedAppAndAutoFillSettings.sharedInstance.showDatabaseStatusIcon) {
        if([SharedAppAndAutoFillSettings.sharedInstance.quickLaunchUuid isEqualToString:database.uuid]) {
            [ret addObject:[UIImage imageNamed:@"rocket"]];
            [tnts addObject:NSNull.null];
        }
        
        if(database.readOnly) {
            if (@available(iOS 13.0, *)) {
                [ret addObject:[UIImage systemImageNamed:@"eyeglasses"]];
            } else {
                [ret addObject:[UIImage imageNamed:@"glasses"]];
            }

            [tnts addObject:NSNull.null];
        }
    }
    
    if (database.outstandingUpdateId) {
        [ret addObject:[UIImage imageNamed:@"upload"]];
        [tnts addObject:UIColor.orangeColor];
    }
    
    if (syncState == kSyncOperationStateInProgress || syncState == kSyncOperationStateError || syncState == kSyncOperationStateBackgroundButUserInteractionRequired || syncState == kSyncOperationStateUserCancelled) {
        [ret addObject:[UIImage imageNamed:@"syncronize"]];
        [tnts addObject:syncState == kSyncOperationStateError ? UIColor.redColor : (syncState == kSyncOperationStateInProgress ? NSNull.null : UIColor.orangeColor)];
    }
    
    if(tints) {
        *tints = tnts;
    }
    
    return ret;
}

- (NSString*)getDatabaseCellSubtitleField:(SafeMetaData*)database field:(DatabaseCellSubtitleField)field {
    switch (field) {
        case kDatabaseCellSubtitleFieldNone:
            return nil;
            break;
        case kDatabaseCellSubtitleFieldFileName:
            return database.fileName;
            break;
        case kDatabaseCellSubtitleFieldLastModifiedDate:
            return [self getModifiedDate:database];
            break;
        case kDatabaseCellSubtitleFieldLastModifiedDatePrecise:
            return [self getModifiedDatePrecise:database];
            break;
        case kDatabaseCellSubtitleFieldFileSize:
            return [self getLocalWorkingCopyFileSize:database];
            break;
        case kDatabaseCellSubtitleFieldStorage:
            return [self getStorageString:database];
            break;
        default:
            return @"<Unknown Field>";
            break;
    }
}

- (NSString*)getModifiedDate:(SafeMetaData*)safe {
    NSDate* mod;
    [SyncManager.sharedInstance isLocalWorkingCacheAvailable:safe modified:&mod];
    return mod ? mod.friendlyDateStringVeryShort : @"";
}

- (NSString*)getModifiedDatePrecise:(SafeMetaData*)safe {
    NSDate* mod;
    [SyncManager.sharedInstance isLocalWorkingCacheAvailable:safe modified:&mod];
    return mod ? mod.friendlyDateTimeStringPrecise : @"";
}

- (NSString*)getLocalWorkingCopyFileSize:(SafeMetaData*)safe {
    unsigned long long fileSize;
    NSURL* url = [SyncManager.sharedInstance getLocalWorkingCache:safe modified:nil fileSize:&fileSize];
    return url ? friendlyFileSizeString(fileSize) : @"";
}

- (NSString*)getStorageString:(SafeMetaData*)database {
    return [SafeStorageProviderFactory getStorageDisplayName:database];
}

@end
