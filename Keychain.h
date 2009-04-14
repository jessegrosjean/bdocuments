//
//  Keychain.h
//  WriteRoom
//
//  Created by Jesse Grosjean on 3/16/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//


@interface Keychain : NSObject {
    NSMutableDictionary *keychainData;            // The actual Keychain data backing store.
    NSMutableDictionary *genericPasswordQuery;    // A placeholder for a generic Keychain Item query.
}

+ (id)sharedInstance;

@property (nonatomic, retain) NSMutableDictionary *keychainData;
@property (nonatomic, retain) NSMutableDictionary *genericPasswordQuery;

- (void)setObject:(id)inObject forKey:(id)key;
- (id)objectForKey:(id)key;

// Initializes and resets the default generic Keychain Item data.
- (void)resetKeychainItem;

@end