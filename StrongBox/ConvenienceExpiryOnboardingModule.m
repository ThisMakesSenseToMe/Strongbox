//
//  ConvenienceExpiryOnboardingModule.m
//  Strongbox
//
//  Created by Strongbox on 17/05/2021.
//  Copyright © 2021 Mark McGuill. All rights reserved.
//

#import "ConvenienceExpiryOnboardingModule.h"
#import "ConvenienceExpiryOnboardingViewController.h"
#import "AppPreferences.h"

@interface ConvenienceExpiryOnboardingModule ()

@property Model* model;

@end

@implementation ConvenienceExpiryOnboardingModule

- (nonnull instancetype)initWithModel:(Model *)model {
    self = [super init];
    if (self) {
        self.model = model;
    }
    return self;
}

- (BOOL)shouldDisplay {
    return ( !self.model.metadata.convenienceExpiryOnboardingDone &&
            AppPreferences.sharedInstance.isPro &&
            self.model.metadata.isConvenienceUnlockEnabled &&
            self.model.metadata.convenienceExpiryPeriod == -1 &&
            self.model.metadata.conveniencePasswordHasBeenStored &&
            self.model.metadata.convenienceMasterPassword.length ); 
}

- (nonnull UIViewController *)instantiateViewController:(nonnull OnboardingModuleDoneBlock)onDone {
    UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"ConvenienceExpiryOnboarding" bundle:nil];
    ConvenienceExpiryOnboardingViewController* vc = [storyboard instantiateInitialViewController];
    
    vc.onDone = onDone;
    vc.model = self.model;
    
    return vc;
}

@end
