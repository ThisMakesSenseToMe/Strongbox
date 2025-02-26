//
//  OnboardingAutoFillViewController.h
//  MacBox
//
//  Created by Strongbox on 22/11/2020.
//  Copyright © 2020 Mark McGuill. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MacDatabasePreferences.h"
#import "ViewModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface OnboardingAutoFillViewController : NSViewController

@property NSString* databaseUuid;
@property ViewModel* viewModel;

@end

NS_ASSUME_NONNULL_END
