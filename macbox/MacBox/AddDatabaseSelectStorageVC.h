//
//  AddDatabaseSelectStorageVC.h
//  MacBox
//
//  Created by Strongbox on 03/02/2021.
//  Copyright © 2021 Mark McGuill. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SafeStorageProvider.h"
#import "StorageBrowserItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface AddDatabaseSelectStorageVC : NSViewController

+ (instancetype)newViewController;

@property id<SafeStorageProvider> provider;
@property (nonatomic, copy) void (^onDone)(BOOL success, StorageBrowserItem*_Nullable selectedItem);


@end

NS_ASSUME_NONNULL_END
