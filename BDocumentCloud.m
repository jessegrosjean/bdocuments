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

#pragma mark Class Methods

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

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
		//serviceRootURLString = @"http://localhost:8093/v1/documents";
		serviceRootURLString = @"http://writeroom-com.appspot.com/v1/documents";

		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *cloud = [fileManager.processesApplicationSupportFolder stringByAppendingPathComponent:@"Cloud"];
		
		localDocumentsPath = [cloud stringByAppendingPathComponent:@"Documents"];
		localDocumentShadowsPath = [cloud stringByAppendingPathComponent:@"Shadows"];
		localDocumentsConflictsPath = [cloud stringByAppendingPathComponent:@"Conflicts"];
		if (![fileManager createDirectoriesForPath:localDocumentsPath]) {
			return nil;
		}
		if (![fileManager createDirectoriesForPath:localDocumentShadowsPath]) {
			return nil;
		}
		if (![fileManager createDirectoriesForPath:localDocumentsConflictsPath]) {
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

- (NSDictionary *)POSTDocumentEdit:(NSDictionary *)edit forKey:(NSString *)key error:(NSError **)error {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/edits", serviceRootURLString, key]]];
	NSHTTPURLResponse *response;
	NSData *responseData;
	
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:[[BDocumentCloud URLencodedPOSTBody:edit] dataUsingEncoding:NSUTF8StringEncoding]];
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
	
	if ([content writeToFile:documentPath atomically:NO encoding:NSUTF8StringEncoding error:error]) {
		[NSFileManager setString:documentID forKey:@"BDocumentID" atPath:documentPath traverseLink:YES];
		if (name) [NSFileManager setString:name forKey:@"BDocumentName" atPath:documentPath traverseLink:YES];
		[NSFileManager setString:[version description] forKey:@"BDocumentVersion" atPath:documentPath traverseLink:YES];
		
		[fileManager removeFileAtPath:documentShadowPath handler:nil];
		
		if (![fileManager copyPath:documentPath toPath:documentShadowPath handler:nil]) {
			BLogError(@"Failed to update local shadow document at path %@", documentShadowPath);
			return NO;
		} else {
			if (name) [NSFileManager setString:name forKey:@"BDocumentName" atPath:documentShadowPath traverseLink:YES];
		}
	} else {
		BLogError(@"Failed to update local document at path %@", documentPath);
		return NO;
	}
	
	[[[NSDocumentController sharedDocumentController] documentForURL:[NSURL fileURLWithPath:documentPath]] checkForModificationOfFileOnDisk];
	
	return YES;
}

- (void)sync:(NSError **)error {
	[self performSelector:@selector(sync2:) withObject:nil afterDelay:0];
}

- (void)sync2:(NSError **)error {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	BDiffMatchPatch *diffMatchPatch = [[[BDiffMatchPatch alloc] init] autorelease];

	NSArray *localDocuments = [fileManager contentsOfDirectoryAtPath:localDocumentsPath error:error];
	if (!localDocuments) {
		BLogError(@"Failed to get local document list, aborting sync");
		return;
	}
	
	NSMutableDictionary *serverDocumentsByID = [[[self GETDocuments:error] mutableCopy] autorelease];
	if (!serverDocumentsByID) {
		BLogError(@"Failed to get document list from server, aborting sync");
		return;
	}
	
	for (NSString *each in localDocuments) {
		NSString *eachLocalPath = [localDocumentsPath stringByAppendingPathComponent:each];
		NSString *eachLocalID = [NSFileManager stringForKey:@"BDocumentID" atPath:eachLocalPath traverseLink:YES];
		
		if ([eachLocalID length] > 0) {
			NSString *eachLocalContent = [NSString stringWithContentsOfFile:eachLocalPath encoding:NSUTF8StringEncoding error:error];
			NSString *eachLocalVersion = [NSFileManager stringForKey:@"BDocumentVersion" atPath:eachLocalPath traverseLink:YES];
			//NSString *eachLocalName = [NSFileManager stringForKey:@"BDocumentName" atPath:eachLocalPath traverseLink:YES];
			NSString *eachLocalShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:eachLocalID];
			NSString *eachLocalShadowContent = [NSString stringWithContentsOfFile:eachLocalShadowPath encoding:NSUTF8StringEncoding error:error];
			//NSString *eachLocalShadowName = [NSFileManager stringForKey:@"BDocumentName" atPath:eachLocalShadowPath traverseLink:YES];
			NSString *serverVersion = [[[serverDocumentsByID objectForKey:eachLocalID] objectForKey:@"version"] description];
			
			if (!serverVersion) {
				if (![eachLocalContent isEqualToString:eachLocalShadowContent]) {
					if (![fileManager copyPath:eachLocalPath toPath:[localDocumentsConflictsPath stringByAppendingPathComponent:eachLocalID] handler:nil]) {
						BLogError(@"Local changes to document are being lost because document was deleted from server %@ and failed to copy to %@", eachLocalID, [localDocumentsConflictsPath stringByAppendingPathComponent:eachLocalID]);
					} else {
						BLogError(@"Local changes to document %@ as being saved to Conflicts because document was deleted from server but there are local changes", eachLocalID);
					}
				}
				if (![fileManager removeItemAtPath:eachLocalPath error:error]) {
					BLogError(@"Failed to remove local document deleted from server %@", eachLocalPath);
				}
				if (![fileManager removeItemAtPath:eachLocalShadowPath error:error]) {
					BLogError(@"Failed to remove local shadow document deleted from server %@", eachLocalShadowPath);							
				}
			} else {
				if (![eachLocalContent isEqualToString:eachLocalShadowContent]) {
					NSMutableArray *diffs = [diffMatchPatch patchMakeText1:eachLocalShadowContent text2:eachLocalContent];
					NSString *patch = [diffMatchPatch patchToText:diffs];
					NSMutableDictionary *patchResultsDocument = [[[self POSTDocumentEdit:[NSDictionary dictionaryWithObjectsAndKeys:patch, @"patch", eachLocalVersion, @"version", nil] forKey:eachLocalID error:error] mutableCopy] autorelease];

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
						BLogError(@"Failed to apply local patch to server document %@", eachLocalID);
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

#pragma mark Lifecycle Callback

- (void)applicationDidFinishLaunching {
	[[NSMenu menuForMenuExtensionPoint:@"com.blocks.BDocuments.menus.main.share"] setDelegate:self];	
	//[self menuNeedsUpdate:[NSMenu menuForMenuExtensionPoint:@"com.blocks.BDocuments.menus.main.share"]];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	for (NSMenuItem *each in [menu itemArray]) {
		[menu removeItem:each];
	}
	
	NSArray *localDocuments = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:localDocumentsPath error:nil];
	
	for (NSString *each in localDocuments) {
		NSString *eachLocalPath = [localDocumentsPath stringByAppendingPathComponent:each];
		NSString *eachName = [NSFileManager stringForKey:@"BDocumentName" atPath:eachLocalPath traverseLink:YES];
		if ([eachName length] > 0) {
			NSMenuItem *eachMenuItem = [[NSMenuItem alloc] initWithTitle:eachName action:@selector(openCloudDocument:) keyEquivalent:@""];
			[eachMenuItem setRepresentedObject:eachLocalPath];
			[eachMenuItem setTarget:self];
			[menu addItem:eachMenuItem];
		}
	}
	
	[menu addItem:[NSMenuItem separatorItem]];
	
	[menu addItemWithTitle:BLocalizedString(@"Sync...", nil) action:@selector(sync:) keyEquivalent:@""];
}

- (IBAction)openCloudDocument:(NSMenuItem *)sender {
	NSError *error = nil;
	if (![[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:[sender representedObject]] display:YES error:&error]) {
		[[NSDocumentController sharedDocumentController] presentError:error];
	}
}

@end