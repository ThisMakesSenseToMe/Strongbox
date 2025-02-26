//
//  CSVImporter.m
//  MacBox
//
//  Created by Strongbox on 21/10/2021.
//  Copyright © 2021 Mark McGuill. All rights reserved.
//

#import "CSVImporter.h"
#import "Csv.h"
#import "Utils.h"

@implementation CSVImporter

+ (Node*)importFromUrl:(NSURL*)url error:(NSError**)error {
    NSArray *rows = [NSArray arrayWithContentsOfCSVURL:url options:CHCSVParserOptionsSanitizesFields | CHCSVParserOptionsUsesFirstLineAsKeys];

    if (rows == nil) {
        NSLog(@"error parsing file...");
        if ( error ) {
            *error = [Utils createNSError:@"Could not read any rows from file" errorCode:-1];
        }
    }
    else if(rows.count == 0){
        NSString* loc = NSLocalizedString(@"mac_csv_file_contains_zero_rows", @"CSV File Contains Zero Rows. Cannot Import.");
        
        NSLog(@"CSV File Contains Zero Rows. Cannot Import.");
        if ( error ) {
            *error = [Utils createNSError:loc errorCode:-1];
        }
    }
    else {
        CHCSVOrderedDictionary *firstRow = [rows firstObject];
        
        if([firstRow objectForKey:kCSVHeaderTitle] ||
           [firstRow objectForKey:kCSVHeaderUsername] ||
           [firstRow objectForKey:kCSVHeaderUrl] ||
           [firstRow objectForKey:kCSVHeaderEmail] ||
           [firstRow objectForKey:kCSVHeaderPassword] ||
           [firstRow objectForKey:kCSVHeaderNotes]) {

            Node* root = [CSVImporter importRecordsFromCsvRows:rows];

            return root;
        }
        else {
            NSString* loc = NSLocalizedString(@"mac_no_valid_csv_rows_found", @"No valid rows found. Ensure CSV file contains a header row and at least one of the required fields.");
            NSLog(@"No valid rows found. Ensure CSV file contains a header row and at least one of the required fields.");
            if ( error ) {
                *error = [Utils createNSError:loc errorCode:-1];
            }
        }
    }
    
    return nil;
}

+ (Node*_Nullable)importRecordsFromCsvRows:(NSArray<CHCSVOrderedDictionary*>*)rows {
    Node* root = Node.rootWithDefaultKeePassEffectiveRootGroup;
    Node* effectiveRootGroup = root.childGroups.firstObject;
    
    for (CHCSVOrderedDictionary* row  in rows) {
        NSString* actualTitle = [row objectForKey:kCSVHeaderTitle];
        NSString* actualUsername = [row objectForKey:kCSVHeaderUsername];
        NSString* actualUrl = [row objectForKey:kCSVHeaderUrl];
        NSString* actualEmail = [row objectForKey:kCSVHeaderEmail];
        NSString* actualPassword = [row objectForKey:kCSVHeaderPassword];
        NSString* actualNotes = [row objectForKey:kCSVHeaderNotes];
        
        actualTitle = actualTitle ? actualTitle : @"Unknown Title (Imported)";
        actualUsername = actualUsername ? actualUsername : @"";
        actualUrl = actualUrl ? actualUrl : @"";
        actualEmail = actualEmail ? actualEmail : @"";
        actualPassword = actualPassword ? actualPassword : @"";
        actualNotes = actualNotes ? actualNotes : @"";
        
        NodeFields* fields = [[NodeFields alloc] initWithUsername:actualUsername
                                                              url:actualUrl
                                                         password:actualPassword
                                                            notes:actualNotes
                                                            email:actualEmail];
        
    
        
        Node* record = [[Node alloc] initAsRecord:actualTitle parent:effectiveRootGroup fields:fields uuid:nil];
        [effectiveRootGroup addChild:record keePassGroupTitleRules:YES];
    }
    
    return root;
}

@end
