//
//  Document.m
//  Documents
//
//  Created by Jesse Grosjean on 4/22/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "SyncedDocument.h"
#import "SyncedDocumentsController.h"
#import "DiffMatchPatch.h"
#import "NSString+SBJSON.h"
#import "HTTPClient.h"


@interface SyncedDocumentsController (DocumentsControllerDocumentPrivate)

- (HTTPClient *)POSTServerDocument:(SyncedDocument *)aDocument;
- (HTTPClient *)GETServerDocument:(SyncedDocument *)aDocument;
- (HTTPClient *)POSTServerDocumentEdits:(SyncedDocument *)aDocument;
- (HTTPClient *)GETServerDocumentEdits:(SyncedDocument *)aDocument;
- (HTTPClient *)DELETEServerDocument:(SyncedDocument *)aDocument;
- (void)noteConflicts:(NSString *)patches;

@end

@implementation SyncedDocument

- (void)awakeFromInsert {
	[super awakeFromInsert];

	NSDate *now = [NSDate date];
	[self setPrimitiveValue:now forKey:@"created"];
	[self setPrimitiveValue:now forKey:@"modified"];
//	[self setPrimitiveValue:@"" forKey:@"name"];
//	[self setPrimitiveValue:@"" forKey:@"content"];
//	[self setPrimitiveValue:@"" forKey:@"tags"];
//	[self setPrimitiveValue:@"" forKey:@"users"];

	//	[self setPrimitiveValue:@"project:\n\t- one @done @home\n\t- two\n\t- three" forKey:@"content"];
	//	[self setPrimitiveValue:@"jesse" forKey:@"name"];
}

- (void)willSave {
	[super willSave];
	[self setPrimitiveValue:[NSDate date] forKey:@"modified"];
}

@dynamic name;

- (NSString *)displayName {
	NSString *name = self.name;
	
	if (!name) {
		NSRange firstParagraphRange = [self.content paragraphRangeForRange:NSMakeRange(0, 0)];
		NSString *displayName = [[self.content substringWithRange:firstParagraphRange] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if ([displayName length] > 250) {
			displayName = [displayName substringToIndex:250];
		} else if ([displayName length] == 0) {
			displayName = NSLocalizedString(@"Untitled", nil);
		}
		
		return displayName;
	}
	
	return name;
}

@dynamic created;
@dynamic modified;
@dynamic content;
@dynamic tags;
@dynamic users;
@dynamic shadowID;
@dynamic shadowVersion;
@dynamic shadowName;
@dynamic shadowContent;
@dynamic shadowTags;
@dynamic shadowUsers;
@synthesize serverVersion;

#pragma mark Sharing

- (NSDictionary *)toIndexDictionary {
	return [NSDictionary dictionaryWithObjectsAndKeys:[[[[self objectID] URIRepresentation] path] lastPathComponent], @"id", [self displayName], @"name", nil];
}

- (NSDictionary *)toDocumentDictionary {
	return [NSDictionary dictionaryWithObjectsAndKeys:[[[[self objectID] URIRepresentation] path] lastPathComponent], @"id", self.displayName, @"name", self.content, @"content"];
}

#pragma mark Edits

- (NSDictionary *)localEdits {
	if (self.shadowID != nil && self.shadowVersion != nil) {
		NSMutableDictionary *edits = [NSMutableDictionary dictionaryWithObject:self.shadowVersion forKey:@"version"];
		
		if (![self.name isEqualToString:self.shadowName]) {
			[edits setObject:self.name forKey:@"name"];
		}
		
		if (![self.content isEqualToString:self.shadowContent]) {
			DiffMatchPatch *diffMatchPatch = [[[DiffMatchPatch alloc] init] autorelease];
			NSString *patches = [diffMatchPatch patchToText:[diffMatchPatch patchMakeText1:self.shadowContent text2:self.content]];
			[edits setObject:patches forKey:@"patches"];
		}

		if ([edits count] > 1) {
			return edits;
		}
	}
	return nil;
}

- (BOOL)hasServerEdits {
	return [self.shadowVersion integerValue] != self.serverVersion;
}

#pragma mark Sync Process

@synthesize isDeletedFromServer;

- (BOOL)isServerDocument {
	return self.shadowID != nil;
}

@dynamic userDeleted;

- (BOOL)isInsertedFromServer {
	return self.serverVersion != -1 && self.shadowVersion == nil;
}

- (HTTPClient *)buildSyncRequest {
	SyncedDocumentsController *documentsController = [SyncedDocumentsController sharedInstance];
	NSDictionary *localEdits = [self localEdits];
	NSError *error = nil;
	
	if (self.isDeletedFromServer) {
		if (localEdits != nil) {
			self.isDeletedFromServer = NO;
			return [documentsController POSTServerDocument:self];
		} else {
			if (![documentsController deleteDocument:self error:&error]) {
				NSLog([error description]);
			}
			return nil;
		}
	} else if ([self.userDeleted boolValue]) {
		if ([self hasServerEdits]) {
			self.userDeleted = [NSNumber numberWithBool:NO];
			if (![documentsController save:&error]) {
				NSLog([error description]);
			}
			return [documentsController GETServerDocument:self];
		} else {
			return [documentsController DELETEServerDocument:self];
		}
	}
	
	if (!self.isServerDocument) {
		return [documentsController POSTServerDocument:self];
	} else if (self.isInsertedFromServer) {
		return [documentsController GETServerDocument:self];
	}
	
	if (localEdits != nil) {
		return [documentsController POSTServerDocumentEdits:self];
	} else if (self.hasServerEdits) {
		return [documentsController GETServerDocumentEdits:self];
	}
	
	return nil;
}

- (void)processSyncResponse:(NSData *)data {
	SyncedDocumentsController *documentsController = [SyncedDocumentsController sharedInstance];
	NSError *error = nil;
	
	if ([self.userDeleted boolValue]) {
		if (![documentsController deleteDocument:self error:&error]) {
			NSLog([error description]);
		}
		return;
	}
	
	NSDictionary *serverDocumentState = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];
	
	if ([serverDocumentState objectForKey:@"id"]) {
		self.shadowID = [serverDocumentState objectForKey:@"id"];
	}
	
	if ([serverDocumentState objectForKey:@"version"]) {
		self.shadowVersion = [serverDocumentState objectForKey:@"version"];
		self.serverVersion = [self.shadowVersion integerValue];
	}
	
	if ([serverDocumentState objectForKey:@"content"]) {
		self.shadowContent = [serverDocumentState objectForKey:@"content"];
		self.content = self.shadowContent;
	} else if ([serverDocumentState objectForKey:@"patches"] && [[serverDocumentState objectForKey:@"patches"] length] > 0) {
		DiffMatchPatch *diffMatchPatch = [[[DiffMatchPatch alloc] init] autorelease];
		NSMutableArray *patches = [diffMatchPatch patchFromText:[serverDocumentState objectForKey:@"patches"]];
		self.shadowContent = [[diffMatchPatch patchApply:patches text:self.shadowContent] objectAtIndex:0];
		self.content = self.shadowContent;
	}
	
	if ([serverDocumentState objectForKey:@"name"]) {
		self.shadowName = [serverDocumentState objectForKey:@"name"];
		self.name = self.shadowName;
	}
	
	if (!self.managedObjectContext) {
		[documentsController.managedObjectContext insertObject:self];
	}
	
	if (![documentsController save:&error]) {
		NSLog([error description]);
	}
	
	// Sync delegate should listen to managed object context, and upadate file system according to noticed changes.
	//[documentsController.delegate documentsControllerSyncUpdateOrInsertLocalDocument:self originalDocumentID:originalDocumentID];
	
	if ([serverDocumentState objectForKey:@"conflicts"]) {
		[documentsController noteConflicts:[serverDocumentState objectForKey:@"conflicts"]];
	}
}

@end

@implementation SyncedDocumentsController (DocumentsControllerDocumentPrivate)

- (HTTPClient *)POSTServerDocument:(SyncedDocument *)aDocument {
	NSMutableURLRequest *postNewDocumentRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents", self.serviceRootURLString]]];
	HTTPClient *postNewDocumentClient = [HTTPClient clientWithRequest:postNewDocumentRequest];
	[postNewDocumentClient setPostDataJSON:[NSDictionary dictionaryWithObjectsAndKeys:aDocument.displayName, @"name", aDocument.content, @"content", nil]];
	[postNewDocumentClient setUserData:aDocument];
	return postNewDocumentClient;
}

- (HTTPClient *)GETServerDocument:(SyncedDocument *)aDocument {
	NSMutableURLRequest *getDocumentRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@", self.serviceRootURLString, aDocument.shadowID]]];
	HTTPClient *getDocumentRequestClient = [HTTPClient clientWithRequest:getDocumentRequest];
	[getDocumentRequestClient setUserData:aDocument];
	return getDocumentRequestClient;
}

- (HTTPClient *)POSTServerDocumentEdits:(SyncedDocument *)aDocument {
	NSMutableURLRequest *postEditsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@/edits", self.serviceRootURLString, aDocument.shadowID]]];
	HTTPClient *postEditsRequestClient = [HTTPClient clientWithRequest:postEditsRequest];
	[postEditsRequestClient setPostDataJSON:aDocument.localEdits];
	[postEditsRequestClient setUserData:aDocument];
	return postEditsRequestClient;
}

- (HTTPClient *)GETServerDocumentEdits:(SyncedDocument *)aDocument {
	NSMutableURLRequest *getServerEditsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@/edits/?start=%i&end=%i", self.serviceRootURLString, aDocument.shadowID, [aDocument.shadowVersion integerValue] + 1, aDocument.serverVersion]]];
	HTTPClient *getServerEditsClient = [HTTPClient clientWithRequest:getServerEditsRequest];
	[getServerEditsClient setUserData:aDocument];
	return getServerEditsClient;
}

- (HTTPClient *)DELETEServerDocument:(SyncedDocument *)aDocument {
 	NSMutableURLRequest *deleteDocumentRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@?version=%@", self.serviceRootURLString, aDocument.shadowID, aDocument.shadowVersion]]];
	[deleteDocumentRequest setHTTPMethod:@"DELETE"];
	HTTPClient *deleteDocumentClient = [HTTPClient clientWithRequest:deleteDocumentRequest];
	[deleteDocumentClient setUserData:aDocument];
	return deleteDocumentClient;
}

- (void)noteConflicts:(NSString *)patches {
	[conflicts appendString:patches];
}

@end