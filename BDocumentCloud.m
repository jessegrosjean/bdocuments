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

- (NSArray *)GETDocuments:(NSError **)error {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serviceRootURLString]];
	NSHTTPURLResponse *response;
	NSData *responseData;
	
	if (responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error]) {
		NSString *responseBody = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
		NSArray *documents = [[[SBJSON alloc] init] objectWithString:responseBody error:error];
		return documents;
	}
	
	return nil;
}

- (NSDictionary *)POSTDocument:(NSDictionary *)document error:(NSError **)error {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serviceRootURLString]];	
	NSHTTPURLResponse *response;

	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:[[BDocumentCloud URLencodedPOSTBody:document] dataUsingEncoding:NSUTF8StringEncoding]];

	if (NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error]) {
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

#pragma mark Sync

- (BOOL)replaceLocalDocument:(NSString *)oldDocumentPath withDocument:(NSDictionary *)document error:(NSError **)error {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	NSString *documentID = [[document objectForKey:@"id"] description];
	NSString *name = [document objectForKey:@"name"];
	NSString *content = [document objectForKey:@"content"];
	NSNumber *version = [document objectForKey:@"version"];
	//		NSDate *created = [document objectForKey:@"created"];
	//		NSDate *modified = [document objectForKey:@"modified"];
	
	if (!name) {
		name = [oldDocumentPath lastPathComponent];
	}

	if (!content) {
		content = [NSString stringWithContentsOfFile:oldDocumentPath encoding:NSUTF8StringEncoding error:error];
	}
	
	if (oldDocumentPath) {
		if (![fileManager removeFileAtPath:oldDocumentPath handler:nil]) {
			BLogError(@"error");
		}
	}
	
	NSString *documentPath = [localDocumentsPath stringByAppendingPathComponent:name];
	
	if ([content writeToFile:documentPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
		[NSFileManager setString:documentID forKey:@"BDocumentID" atPath:documentPath traverseLink:YES];
		[NSFileManager setString:[version description] forKey:@"BDocumentVersion" atPath:documentPath traverseLink:YES];
		
		NSString *documentShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:documentID];
		[fileManager removeFileAtPath:documentShadowPath handler:nil];
		if (![fileManager copyPath:documentPath toPath:documentShadowPath handler:nil]) {
			return NO;
		}
	} else {
		return NO;
	}
	
	return YES;
}

- (void)sync:(NSError **)bigError {
	NSError *error = nil;
	BDiffMatchPatch *dmp = [[[BDiffMatchPatch alloc] init] autorelease];
	NSFileManager *fileManager = [NSFileManager defaultManager];

	NSMutableDictionary *serverDocumentsByID = [NSMutableDictionary dictionary];
	NSArray *serverDocumentsListing = [self GETDocuments:&error];

	if (!serverDocumentsListing) {
		if (error) {
			BLogError([error description]);
		} else {
			BLogError(@"Failed GETDocuments:");
		}
		return;
	}
	
	for (NSDictionary *eachDocuent in serverDocumentsListing) {
		[serverDocumentsByID setObject:eachDocuent forKey:[[eachDocuent objectForKey:@"location"] lastPathComponent]];
	}
	
	NSArray *localDocuments = [fileManager contentsOfDirectoryAtPath:localDocumentsPath error:&error];
	if (!localDocuments) {
		if (error) {
			BLogError([error description]);
		} else {
			BLogError(@"Failed contentsOfDirectoryAtPath:");
		}
		return;
	}

	for (NSString *each in localDocuments) {
		if ([each characterAtIndex:0] != '.') {
			NSString *eachLocalPath = [localDocumentsPath stringByAppendingPathComponent:each];
			NSString *eachLocalContent = [NSString stringWithContentsOfFile:eachLocalPath encoding:NSUTF8StringEncoding error:&error];
			NSString *eachID = [NSFileManager stringForKey:@"BDocumentID" atPath:eachLocalPath traverseLink:YES];
			NSString *eachVersion = [NSFileManager stringForKey:@"BDocumentVersion" atPath:eachLocalPath traverseLink:YES];
			
			if (eachID != nil && [eachID length] > 0) {
				// Document has been synced before, so compare against shadow
				NSString *eachLocalShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:eachID];
				NSString *eachLocalShadowContent = [NSString stringWithContentsOfFile:eachLocalShadowPath encoding:NSUTF8StringEncoding error:&error];
				
				if (![eachLocalContent isEqualToString:eachLocalShadowContent]) {
					// Push local changes.
					NSMutableArray *patches = [dmp patchMakeText1:eachLocalShadowContent text2:eachLocalContent];
					NSString *patch = [dmp patchToText:patches];
					NSDictionary *putResults = [self PUTDocument:[NSDictionary dictionaryWithObjectsAndKeys:patch, @"patch", eachVersion, @"version", nil] forKey:eachID error:&error];
					NSArray *results = [putResults objectForKey:@"results"];
					for (NSNumber *each in results) {
						if (![each boolValue]) {
							BLogError(@"failed to apply all patches");
						}
					}
					
					if (![self replaceLocalDocument:eachLocalPath withDocument:putResults error:&error]) {
						BLogError(@"error");
					}
				} else {
					// Pull server changes if needed.
					NSString *serverVersion = [[[serverDocumentsByID objectForKey:eachID] objectForKey:@"version"] description];
					if (![eachVersion isEqualToString:serverVersion]) {
						NSDictionary *eachServerDocument = [self GETDocumentForKey:eachID error:&error];
						if (![self replaceLocalDocument:eachLocalPath withDocument:eachServerDocument error:&error]) {
							BLogError(@"error");
						}
					}
				}
				[serverDocumentsByID removeObjectForKey:eachID];
			} else {
				// New document, post to server, create shadow.
				NSDictionary *document = [self POSTDocument:[NSMutableDictionary dictionaryWithObjectsAndKeys:each, @"name", eachLocalContent, @"content", nil] error:&error];
				if (![self replaceLocalDocument:eachLocalPath withDocument:document error:&error]) {
					BLogError(@"error");
				}
			}
		}
	}
	
	for (NSString *eachKey in [serverDocumentsByID keyEnumerator]) {
		NSDictionary *eachServerDocument = [self GETDocumentForKey:eachKey error:&error];
		if (![self replaceLocalDocument:nil withDocument:eachServerDocument error:&error]) {
			BLogError(@"error");
		}
	}
	
	 
	 // for local document
	 // if shadow exists
	 // compute diff against shadow
	 // if different
	 // put diff to server.
	 // look at results, and save patches that didn't patch.
	 // else
	 // post to sever
	 // get key from post response
	 // create shadow
	 // update local metadata
	 
	 // for local metadata document
	 // if it doesn't exist
	 
	 
	 // for cloud metadata document
	 // if local version exists:
	 // if version number doesn't match cloud version number
	 // download cloud version
	 // replace local and shodow
	 // update localmetadata
	 // else
	 // download cloud document.
	 // replace local and shodow
	 // update localmetadata
}

@end