//
//  BDocumentCloud.m
//  BDocuments
//
//  Created by Jesse Grosjean on 9/29/08.
//  Copyright 2008 Hog Bay Software. All rights reserved.
//

#import "BDocumentCloud.h"
#import "BDiffMatchPatch.h"
#import "SBJSON.h"


@implementation BDocumentCloud

+ (NSString *)stringByURLEncodingStringParameter:(NSString *)str {
	// From Google Data Objective-C client 
	// NSURL's stringByAddingPercentEscapesUsingEncoding: does not escape
	// some characters that should be escaped in URL parameters, like / and ?; 
	// we'll use CFURL to force the encoding of those
	//
	// We'll explicitly leave spaces unescaped now, and replace them with +'s
	//
	// Reference: http://www.ietf.org/rfc/rfc3986.txt
	
	NSString *resultStr = str;
	CFStringRef originalString = (CFStringRef) str;
	CFStringRef leaveUnescaped = CFSTR(" ");
	CFStringRef forceEscaped = CFSTR("!*'();:@&=+$,/?%#[]");
	CFStringRef escapedStr = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, originalString, leaveUnescaped, forceEscaped, kCFStringEncodingUTF8);
	
	if (escapedStr) {
		NSMutableString *mutableStr = [NSMutableString stringWithString:(NSString *)escapedStr];
		CFRelease(escapedStr);
		[mutableStr replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [mutableStr length])];
		resultStr = mutableStr;
	}
	
	return resultStr;
}

+ (NSString *)URLencodedPOSTBody:(NSDictionary *)dictionary {
	NSMutableString *URLencodedPOSTBody = [NSMutableString string];
	BOOL started = NO;
	
	for (NSString *eachKey in [dictionary keyEnumerator]) {
		NSString *eachValue = [BDocumentCloud stringByURLEncodingStringParameter:[dictionary objectForKey:eachKey]];
		eachKey = [BDocumentCloud stringByURLEncodingStringParameter:eachKey];
		
		if (started) {
			[URLencodedPOSTBody appendString:@"&"];
		} else {
			started = YES;
		}
		
		[URLencodedPOSTBody appendFormat:@"%@=%@", eachKey, eachValue];
	}
	
	return URLencodedPOSTBody;
}

- (id)init {
	if (self = [super init]) {
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *cloud = [fileManager.processesApplicationSupportFolder stringByAppendingPathComponent:@"Cloud"];
		localDocumentsPath = [cloud stringByAppendingPathComponent:@"Documents"];
		localDocumentShadowsPath = [cloud stringByAppendingPathComponent:@"Shadows"];
		if (![fileManager createDirectoriesForPath:localDocumentsPath]) {
			return nil;
		}
		if (![fileManager createDirectoriesForPath:localDocumentShadowsPath]) {
			return nil;
		}
	}
	return self;
}

@synthesize serviceRootURLString;
@synthesize localRootURLString;
@synthesize localDocumentsPath;
@synthesize localDocumentShadowsPath;

- (NSDictionary  *)GETDocuments:(NSError **)error {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serviceRootURLString]];
	NSHTTPURLResponse *response;
	NSData *responseData;
	
	if (responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error]) {
		NSString *responseBody = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		NSArray *documents = [[[[SBJSON alloc] init] objectWithString:responseBody error:error] autorelease];
		NSMutableDictionary *documentsByID = [NSMutableDictionary dictionary];
		for (NSDictionary *each in documents) {
			[documentsByID setObject:each forKey:[[each objectForKey:@"location"] lastPathComponent]];
		}
		return documentsByID;
	}
	
	return nil;
}

- (NSDictionary *)POSTDocument:(NSDictionary *)document error:(NSError **)error {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serviceRootURLString]];	
	NSHTTPURLResponse *response;
	NSData *responseData;

	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:[[BDocumentCloud URLencodedPOSTBody:document] dataUsingEncoding:NSUTF8StringEncoding]];

	if (responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error]) {
		return [[[[SBJSON alloc] init] objectWithString:[[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease] error:error] autorelease];
	}
	
//	if (*error != nil && [response statusCode] == 201) { // created
//		return [[[response allHeaderFields] objectForKey:@"Location"] lastPathComponent];
//	}
	
	return nil;
}

- (NSDictionary *)PUTDocument:(NSDictionary *)document forKey:(NSString *)key error:(NSError **)error {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", serviceRootURLString, key]]];
	NSHTTPURLResponse *response;
	NSData *responseData;
	
	[request setHTTPMethod:@"PUT"];
	[request setHTTPBody:[[BDocumentCloud URLencodedPOSTBody:document] dataUsingEncoding:NSUTF8StringEncoding]];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

	if (responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error]) {
		return [[[[SBJSON alloc] init] objectWithString:[[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease] error:error] autorelease];
	}
	
	return nil;
}

- (NSDictionary *)GETDocumentForKey:(NSString *)key error:(NSError **)error {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", serviceRootURLString, key]]];
	NSHTTPURLResponse *response;
	NSData *responseData;
	
	if (responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error]) {
		NSString *responseBody = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
		NSDictionary *document = [[[SBJSON alloc] init] objectWithString:responseBody error:error];
		return document;
	}
	
	return nil;
}

- (BOOL)DELETEDocumentForKey:(NSString *)key error:(NSError **)error {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", serviceRootURLString, key]]];
	NSHTTPURLResponse *response;
	NSData *responseData;

	[request setHTTPMethod:@"DELETE"];

	if (responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error]) {
		return YES;
	}
	
	return NO;
}

#pragma mark Sync

- (BOOL)updateLocalWithServerState:(NSDictionary *)document error:(NSError **)error {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *documentID = [[document objectForKey:@"id"] description];
	NSString *name = [document objectForKey:@"name"];
	NSString *content = [document objectForKey:@"content"];
	NSNumber *version = [document objectForKey:@"version"];
		
	if (!documentID) {
		documentID = [[document objectForKey:@"location"] lastPathComponent];
	}
		
	NSString *documentPath = [localDocumentsPath stringByAppendingPathComponent:documentID];
	NSString *documentShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:documentID];
	
	if ([content writeToFile:documentPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
		[NSFileManager setString:documentID forKey:@"BDocumentID" atPath:documentPath traverseLink:YES];
		[NSFileManager setString:name forKey:@"BDocumentName" atPath:documentPath traverseLink:YES];
		[NSFileManager setString:[version description] forKey:@"BDocumentVersion" atPath:documentPath traverseLink:YES];
		
		[fileManager removeFileAtPath:documentShadowPath handler:nil];
		
		if (![fileManager copyPath:documentPath toPath:documentShadowPath handler:nil]) {
			BLogError(@"Failed to update local shadow document at path %@", documentShadowPath);
			return NO;
		}
	} else {
		BLogError(@"Failed to update local document at path %@", documentPath);
		return NO;
	}
	
	return YES;
}

- (void)sync:(NSError **)error {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	BDiffMatchPatch *diffMatchPatch = [[[BDiffMatchPatch alloc] init] autorelease];

	NSArray *localDocuments = [fileManager contentsOfDirectoryAtPath:localDocumentsPath error:error];
	if (!localDocuments) {
		return;
	}
	
	NSMutableDictionary *serverDocumentsByID = [[[self GETDocuments:error] mutableCopy] autorelease];
	if (!serverDocumentsByID) {
		return;
	}
	
	for (NSString *each in localDocuments) {
		if ([each characterAtIndex:0] != '.') {
			NSString *eachLocalPath = [localDocumentsPath stringByAppendingPathComponent:each];
			NSString *eachLocalContent = [NSString stringWithContentsOfFile:eachLocalPath encoding:NSUTF8StringEncoding error:error];
			NSString *eachLocalID = [NSFileManager stringForKey:@"BDocumentID" atPath:eachLocalPath traverseLink:YES];
			NSString *eachLocalVersion = [NSFileManager stringForKey:@"BDocumentVersion" atPath:eachLocalPath traverseLink:YES];
//			NSString *eachLocalName = [NSFileManager stringForKey:@"BDocumentName" atPath:eachLocalPath traverseLink:YES];
			NSString *eachLocalShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:eachLocalID];
			NSString *eachLocalShadowContent = [NSString stringWithContentsOfFile:eachLocalShadowPath encoding:NSUTF8StringEncoding error:error];
			
			if ([eachLocalID length] > 0) {
				NSString *serverVersion = [[[serverDocumentsByID objectForKey:eachLocalID] objectForKey:@"version"] description];
				if (!serverVersion) {
					if (![eachLocalContent isEqualToString:eachLocalShadowContent]) {
						BLogError(@"Local changes to document are being lost because document was deleted from server %@", eachLocalID);
					}
					if (![fileManager removeItemAtPath:eachLocalPath error:error]) {
						BLogError(@"Failed to remove local document deleted from server %@", eachLocalPath);
					}
					if (![fileManager removeItemAtPath:eachLocalShadowPath error:error]) {
						BLogError(@"Failed to remove local shadow document deleted from server %@", eachLocalShadowPath);							
					}
				} else {
					if (![eachLocalContent isEqualToString:eachLocalShadowContent]) {
						NSString *patch = [diffMatchPatch patchToText:[diffMatchPatch patchMakeText1:eachLocalShadowContent text2:eachLocalContent]];
						NSMutableDictionary *patchResultsDocument = [[[self PUTDocument:[NSDictionary dictionaryWithObjectsAndKeys:patch, @"patch", eachLocalVersion, @"version", nil] forKey:eachLocalID error:error] mutableCopy] autorelease];
						if (patchResultsDocument) {
							NSArray *results = [patchResultsDocument objectForKey:@"results"];
							for (NSNumber *each in results) {
								if (![each boolValue]) {
									BLogError(@"Failed to fully apply patches to document %@", eachLocalID); // Create backup and allow user to manually resolve conflict.
								}
							}
							
							[patchResultsDocument setObject:eachLocalID forKey:@"id"];
							if (![patchResultsDocument objectForKey:@"content"]) {
								[patchResultsDocument setObject:eachLocalContent forKey:@"content"];
							}
							
							if (![self updateLocalWithServerState:patchResultsDocument error:error]) {
								BLogError(@"Failed to update local copy of document from server %@", eachLocalID); // Bad case... server is now good, but not client.
							}
						} else {
							BLogError(@"Failed to apply patch to document %@", eachLocalID);
						}
					} else {
						if (![eachLocalVersion isEqualToString:serverVersion]) {
							NSDictionary *eachServerDocument = [self GETDocumentForKey:eachLocalID error:error];
							if (!eachServerDocument) {
								BLogError(@"Failed to pull update for document %@", eachLocalID);
							} else if (![self updateLocalWithServerState:eachServerDocument error:error]) {
								BLogError(@"Failed to update local copy of document from server %@", eachLocalID);
							}
						}
					}
					[serverDocumentsByID removeObjectForKey:eachLocalID];
				}
			} else {
				NSDictionary *document = [self POSTDocument:[NSMutableDictionary dictionaryWithObjectsAndKeys:each, @"name", eachLocalContent, @"content", nil] error:error];
				if (!document) {
					BLogError(@"Failed to post local document to server %@", eachLocalPath);
				} else if (![self updateLocalWithServerState:document error:error]) {
					BLogError(@"Failed to update local copy of document from server %@", eachLocalPath);
				}
			}
		}
	}
	
	for (NSString *eachServerID in [serverDocumentsByID keyEnumerator]) {
		NSDictionary *eachServerDocument = [self GETDocumentForKey:eachServerID error:error];
		if (!eachServerDocument) {
			BLogError(@"Failed to get server document %@", eachServerID);
		} else if (![self updateLocalWithServerState:eachServerDocument error:error]) {
			BLogError(@"Failed to update local copy of document from server %@", eachServerID);
		}
	}
}

@end