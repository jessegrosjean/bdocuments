//
//  BDocumentCloud.h
//  BDocuments
//
//  Created by Jesse Grosjean on 9/29/08.
//  Copyright 2008 Hog Bay Software. All rights reserved.
//

#import <Blocks/Blocks.h>


@interface BDocumentCloud : NSObject {
	NSString *serviceRootURLString;
	NSString *localRootURLString;
}

+ (NSString *)stringByURLEncodingStringParameter:(NSString *)str;

@property(retain) NSString *serviceRootURLString;
@property(retain) NSString *localRootURLString;

- (NSArray *)GETDocuments;
- (NSString *)POSTDocument:(NSDictionary *)document;
- (NSArray *)PUTDocument:(NSDictionary *)document forKey:(NSString *)key;
- (NSDictionary *)GETDocumentForKey:(NSString *)key;

- (void)sync;

@end
