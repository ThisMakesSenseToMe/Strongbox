//
//  CustomFieldsViewController.h
//  Strongbox
//
//  Created by Mark on 26/11/2018.
//  Copyright © 2014-2021 Mark McGuill. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CustomField.h"

NS_ASSUME_NONNULL_BEGIN

@interface CustomFieldsViewController : UITableViewController

@property NSArray<CustomField*> *items;
@property (nonatomic, copy) dispatch_block_t onDoneWithChanges;
@property BOOL readOnly;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *buttonAdd;

@end

NS_ASSUME_NONNULL_END
