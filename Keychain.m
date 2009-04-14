//
//  Keychain.m
//  WriteRoom
//
//  Created by Jesse Grosjean on 3/16/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "Keychain.h"
#import <Security/Security.h>

static const UInt8 kKeychainIdentifier[]    = "com.apple.dts.KeychainUI\0";

/*

These are the default constants and their respective types,
available for the kSecClassGenericPassword Keychain Item class:

kSecAttrCreationDate        -        CFDateRef
kSecAttrModificationDate    -        CFDateRef
kSecAttrDescription        -        CFStringRef
kSecAttrComment            -        CFStringRef
kSecAttrCreator            -        CFNumberRef
kSecAttrType                -        CFNumberRef
kSecAttrLabel                -        CFStringRef
kSecAttrIsInvisible        -        CFBooleanRef
kSecAttrIsNegative            -        CFBooleanRef
kSecAttrAccount            -        CFStringRef
kSecAttrService            -        CFStringRef
kSecAttrGeneric            -        CFDataRef

*/

@interface Keychain (PrivateMethods)
/*
The decision behind the following two methods (secItemFormatToDictionary and dictionaryToSecItemFormat) was
to encapsulate the transition between what the detail view controller was expecting (NSString *) and what the
Keychain API expects as a validly constructed container class.
*/
- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert;
- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert;

//Method to push an item to the Keychain or update it.
- (void)writeToKeychain;

@end

@implementation Keychain

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

@synthesize keychainData, genericPasswordQuery;

//#if TARGET_IPHONE_SIMULATOR

- (id)init {
	if (self = [super init]) {
		keychainData = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)writeToKeychain {	
}

- (void)resetKeychainItem {
}

//#else

/*
- (id)init
{
    if (self = [super init])
    {
        // Begin Keychain search setup. The genericPasswordQuery leverages the special user
        // defined object kSecAttrGeneric to distinguish itself between other generic Keychain
        // items which may be included by the same application.
        genericPasswordQuery = [[NSMutableDictionary alloc] init];
        [genericPasswordQuery setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
        NSData *keychainType = [NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)];
        [genericPasswordQuery setObject:keychainType forKey:(id)kSecAttrGeneric];
        // Use the proper search constants, return only the attributes of the first match.
        [genericPasswordQuery setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
        [genericPasswordQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
        
        NSDictionary *tempQuery = [NSDictionary dictionaryWithDictionary:genericPasswordQuery];
        
        NSMutableDictionary *outDictionary = nil;
        
        if (! SecItemCopyMatching((CFDictionaryRef)tempQuery, (CFTypeRef *)&outDictionary) == noErr)
        {
            // Stick these default values into Keychain if nothing found.
            [self resetKeychainItem];
        }
        else
        {
            // load the saved data from Keychain.
            self.keychainData = [self secItemFormatToDictionary:outDictionary];
        }
        [outDictionary release];
    }
    return self;
}

- (void)resetKeychainItem
{
	OSStatus junk = noErr;
    if (!keychainData) 
    {
        self.keychainData = [[NSMutableDictionary alloc] init];
    }
    else if (keychainData)
    {
        NSMutableDictionary *tmpDictionary = [self dictionaryToSecItemFormat:keychainData];
		junk = SecItemDelete((CFDictionaryRef)tmpDictionary);
        NSAssert( junk == noErr || junk == errSecItemNotFound, @"Problem deleting current dictionary." );
    }
    
    // Default generic data for Keychain Item.
    [keychainData setObject:@"Name" forKey:(id)kSecAttrLabel];
    [keychainData setObject:@"Login" forKey:(id)kSecAttrDescription];
    [keychainData setObject:@"bsdname" forKey:(id)kSecAttrAccount];
    [keychainData setObject:@"HomeDir" forKey:(id)kSecAttrService];
    [keychainData setObject:@"This is my Keychain for home mount." forKey:(id)kSecAttrComment];
    [keychainData setObject:@"psswd" forKey:(id)kSecValueData];
}

- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert
{
    // The assumption is that this method will be called with a properly populated dictionary
    // containing all the right key/value pairs for a SecItem.
    
    // Create returning dictionary populated with the attributes.
    NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    
    // Add the Keychain Item class as well as the generic attribute.
    NSData *keychainType = [NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)];
    [returnDictionary setObject:keychainType forKey:(id)kSecAttrGeneric];
    [returnDictionary setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
    
    // Convert the NSString to NSData to fit the API paradigm.
    NSString *passwordString = [dictionaryToConvert objectForKey:(id)kSecValueData];
    [returnDictionary setObject:[passwordString dataUsingEncoding:NSUTF8StringEncoding] forKey:(id)kSecValueData];
    
    return returnDictionary;
}

- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert
{
    // The assumption is that this method will be called with a properly populated dictionary
    // containing all the right key/value pairs for the UI element.
    
    // Remove the generic attribute which distinguishes this Keychain Item with this
    // application.
    // Create returning dictionary populated with the attributes.
    NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    
    // Add the proper search key and class attribute.
    [returnDictionary setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    [returnDictionary setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
    
    // Acquire the password data from the attributes.
    NSData *passwordData = NULL;
    if (SecItemCopyMatching((CFDictionaryRef)returnDictionary, (CFTypeRef *)&passwordData) == noErr)
    {
        // Remove the search, class, and identifier key/value, we don't need them anymore.
        [returnDictionary removeObjectForKey:(id)kSecReturnData];
        
        // Add the password to the dictionary.
        NSString *password = [[[NSString alloc] initWithBytes:[passwordData bytes] length:[passwordData length] 
                                                     encoding:NSUTF8StringEncoding] autorelease];
        [returnDictionary setObject:password forKey:(id)kSecValueData];
    }
    else
    {
        // Don't do anything if nothing is found.
        NSAssert(NO, @"Serious error, nothing is found in the Keychain.\n");
    }
    
    [passwordData release];
    return returnDictionary;
}

- (void)writeToKeychain
{
    NSDictionary *attributes = NULL;
    NSMutableDictionary *updateItem = NULL;
    
    if (SecItemCopyMatching((CFDictionaryRef)genericPasswordQuery, (CFTypeRef *)&attributes) == noErr)
    {
        // First we need the attributes from the Keychain.
        updateItem = [NSMutableDictionary dictionaryWithDictionary:attributes];
        // Second we need to add the appropriate search key/values.
        [updateItem setObject:[genericPasswordQuery objectForKey:(id)kSecClass] forKey:(id)kSecClass];
        
        // Lastly, we need to set up the updated attribute list being careful to remove the class.
        NSMutableDictionary *tempCheck = [self dictionaryToSecItemFormat:keychainData];
        [tempCheck removeObjectForKey:(id)kSecClass];
        
        // An implicit assumption is that you can only update a single item at a time.
        NSAssert( SecItemUpdate((CFDictionaryRef)updateItem, (CFDictionaryRef)tempCheck) == noErr, 
                 @"Couldn't update the Keychain Item." );
    }
    else
    {
        // No previous item found, add the new one.
        NSAssert( SecItemAdd((CFDictionaryRef)[self dictionaryToSecItemFormat:keychainData], NULL) == noErr, 
                 @"Couldn't add the Keychain Item." );
    }
}
*/

// #endif

- (void)setObject:(id)inObject forKey:(id)key 
{
    if (inObject == nil) return;
    id currentObject = [keychainData objectForKey:key];
    if (![currentObject isEqual:inObject])
    {
        [keychainData setObject:inObject forKey:key];
        [self writeToKeychain];
    }
}

- (id)objectForKey:(id)key
{
    return [keychainData objectForKey:key];
}

- (void)dealloc
{
    [keychainData release];
    [genericPasswordQuery release];
    [super dealloc];
}

@end
