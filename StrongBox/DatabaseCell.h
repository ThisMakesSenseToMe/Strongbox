//
//  DatabaseCell.h
//  Strongbox
//
//  Created by Mark on 30/07/2019.
//  Copyright © 2014-2021 Mark McGuill. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SafeMetaData.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kDatabaseCell;

@interface DatabaseCell : UITableViewCell

- (void)populateCell:(SafeMetaData*)database;
- (void)populateCell:(SafeMetaData *)database disabled:(BOOL)disabled;
- (void)populateCell:(SafeMetaData*)database disabled:(BOOL)disabled autoFill:(BOOL)autoFill;

@end

NS_ASSUME_NONNULL_END
