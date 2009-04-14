//
//  CloudDocument.m
//  WriteRoom
//
//  Created by Jesse Grosjean on 3/9/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "CloudDocument.h"
#import "DiffMatchPatch.h"
#import "NSString+SBJSON.h"
#import "HTTPFetcher.h"
#import "Cloud.h"

@interface Cloud (CloudDocumentPrivate)

- (HTTPFetcher *)POSTServerDocument:(CloudDocument *)aDocument;
- (HTTPFetcher *)GETServerDocument:(CloudDocument *)aDocument;
- (HTTPFetcher *)POSTServerDocumentEdits:(CloudDocument *)aDocument;
- (HTTPFetcher *)GETServerDocumentEdits:(CloudDocument *)aDocument;
- (HTTPFetcher *)DELETEServerDocument:(CloudDocument *)aDocument;
- (void)noteConflicts:(NSString *)patches;

@end

@implementation CloudDocument

- (void)dealloc {
	[documentID release];
	[localName release];
	[localShadowName release];
	[localContent release];
	[localShadowContent release];
	[localShadowVersion release];
	[serverVersion release];
	[super dealloc];
}

@synthesize documentID;
@synthesize localName;
@synthesize localShadowName;
@synthesize localContent;
@synthesize localShadowContent;
@synthesize localShadowVersion;
@synthesize serverVersion;

#pragma mark Edits

- (BOOL)hasLocalContentEdits {
	return (self.localContent != nil && self.localShadowContent != nil) && ![self.localContent isEqualToString:self.localShadowContent];
}

- (BOOL)hasLocalNameEdits {
	return (self.localName != nil && self.localShadowName != nil) && ![self.localName isEqualToString:self.localShadowName];
}

- (BOOL)hasLocalEdits {
	return self.hasLocalContentEdits || self.hasLocalNameEdits;
}

- (NSDictionary *)localEdits {
	NSMutableDictionary *edits = [NSMutableDictionary dictionaryWithObject:self.localShadowVersion forKey:@"version"];

	if (self.hasLocalNameEdits) {
		[edits setObject:self.localName forKey:@"name"];
	}
	
	if (self.hasLocalContentEdits) {
		DiffMatchPatch *diffMatchPatch = [[[DiffMatchPatch alloc] init] autorelease];
		NSString *patches = [diffMatchPatch patchToText:[diffMatchPatch patchMakeText1:self.localShadowContent text2:self.localContent]];
		[edits setObject:patches forKey:@"patches"];
	}

	return edits;
}

- (BOOL)hasServerEdits {
	return (self.serverVersion != nil && self.localShadowVersion != nil) && ![self.serverVersion isEqualToString:self.localShadowVersion];
}

#pragma mark Sync Process

@synthesize isScheduledForDeleteOnClient;
@synthesize isDeletedFromServer;
@synthesize isScheduledForInsertOnClient;

- (BOOL)isInsertedFromServer {
	return self.serverVersion != nil && (self.localShadowVersion == nil);
}

- (HTTPFetcher *)buildSyncRequest {
	Cloud *cloud = [Cloud sharedInstance];
	
	if (self.isDeletedFromServer) {
		if ([self hasLocalEdits] && !self.isScheduledForDeleteOnClient) {
			return [cloud POSTServerDocument:self];
		} else {
			[cloud.delegate cloudSyncDeleteLocalDocument:self.documentID];
			return nil;
		}
	} else if (self.isScheduledForDeleteOnClient) {
		if ([self hasServerEdits]) {
			return [cloud GETServerDocument:self];
		} else {
			return [cloud DELETEServerDocument:self];
		}
	}
	
	if (self.isScheduledForInsertOnClient) {
		return [cloud POSTServerDocument:self];
	} else if (self.isInsertedFromServer) {
		return [cloud GETServerDocument:self];
	}
	
	if (self.hasLocalEdits) {
		return [cloud POSTServerDocumentEdits:self];
	} else if (self.hasServerEdits) {
		return [cloud GETServerDocumentEdits:self];
	}
	
	return nil;
}

- (void)processSyncResponse:(NSData *)data {
	Cloud *cloud = [Cloud sharedInstance];
	
	if (self.isScheduledForDeleteOnClient && ![self hasServerEdits]) {
		[cloud.delegate cloudSyncDeleteLocalDocument:self.documentID];
		return;
	}
	
	NSDictionary *serverDocumentState = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];
	NSString *originalDocumentID = self.documentID;
	
	if ([serverDocumentState objectForKey:@"id"]) {
		self.documentID = [serverDocumentState objectForKey:@"id"];
	}
	
	if ([serverDocumentState objectForKey:@"version"]) {
		self.serverVersion = [[serverDocumentState objectForKey:@"version"] description];
		self.localShadowVersion = self.serverVersion;
	}
	
	if ([serverDocumentState objectForKey:@"content"]) {
		self.localContent = [serverDocumentState objectForKey:@"content"];
		self.localShadowContent = [serverDocumentState objectForKey:@"content"];
	} else if ([serverDocumentState objectForKey:@"patches"] && [[serverDocumentState objectForKey:@"patches"] length] > 0) {
		DiffMatchPatch *diffMatchPatch = [[[DiffMatchPatch alloc] init] autorelease];
		NSMutableArray *patches = [diffMatchPatch patchFromText:[serverDocumentState objectForKey:@"patches"]];
		self.localContent = [[diffMatchPatch patchApply:patches text:localShadowContent] objectAtIndex:0];
		self.localShadowContent = self.localContent;
	}
	
	if ([serverDocumentState objectForKey:@"name"]) {
		self.localShadowName = [serverDocumentState objectForKey:@"name"];
		self.localName = self.localShadowName;
	}
	
	[cloud.delegate cloudSyncUpdateOrInsertLocalDocument:self originalDocumentID:originalDocumentID];
	
	if ([serverDocumentState objectForKey:@"conflicts"]) {
		[cloud noteConflicts:[serverDocumentState objectForKey:@"conflicts"]];
	}
}

@end

@implementation Cloud (CloudDocumentPrivate)

- (HTTPFetcher *)POSTServerDocument:(CloudDocument *)aDocument {
	NSMutableURLRequest *postNewDocumentRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents", self.serviceRootURLString]]];
	HTTPFetcher *postNewDocumentFetcher = [HTTPFetcher fetcherWithRequest:postNewDocumentRequest];
	[postNewDocumentFetcher setPostDataJSON:[NSDictionary dictionaryWithObjectsAndKeys:aDocument.localName, @"name", aDocument.localContent, @"content", nil]];
	[postNewDocumentFetcher setUserData:aDocument];
	return postNewDocumentFetcher;
}

- (HTTPFetcher *)GETServerDocument:(CloudDocument *)aDocument {
	NSMutableURLRequest *getDocumentRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@", self.serviceRootURLString, aDocument.documentID]]];
	HTTPFetcher *getDocumentRequestFetcher = [HTTPFetcher fetcherWithRequest:getDocumentRequest];
	[getDocumentRequestFetcher setUserData:aDocument];
	return getDocumentRequestFetcher;
}

- (HTTPFetcher *)POSTServerDocumentEdits:(CloudDocument *)aDocument {
	NSMutableURLRequest *postEditsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@/edits", self.serviceRootURLString, aDocument.documentID]]];
	HTTPFetcher *postEditsRequestFetcher = [HTTPFetcher fetcherWithRequest:postEditsRequest];
	[postEditsRequestFetcher setPostDataJSON:aDocument.localEdits];
	[postEditsRequestFetcher setUserData:aDocument];
	return postEditsRequestFetcher;
}

- (HTTPFetcher *)GETServerDocumentEdits:(CloudDocument *)aDocument {
	NSNumberFormatter *numberFormatter = [[[NSNumberFormatter alloc] init] autorelease];
	NSMutableURLRequest *getServerEditsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@/edits/?start=%@&end=%@", self.serviceRootURLString, aDocument.documentID, [NSString stringWithFormat:@"%i", [[numberFormatter numberFromString:aDocument.localShadowVersion] intValue] + 1], aDocument.serverVersion]]];
	HTTPFetcher *getServerEditsFetcher = [HTTPFetcher fetcherWithRequest:getServerEditsRequest];
	[getServerEditsFetcher setUserData:aDocument];
	return getServerEditsFetcher;
}

- (HTTPFetcher *)DELETEServerDocument:(CloudDocument *)aDocument {
 	NSMutableURLRequest *deleteDocumentRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@?version=%@", self.serviceRootURLString, aDocument.documentID, aDocument.localShadowVersion]]];
	[deleteDocumentRequest setHTTPMethod:@"DELETE"];
	HTTPFetcher *deleteDocumentFetcher = [HTTPFetcher fetcherWithRequest:deleteDocumentRequest];
	[deleteDocumentFetcher setUserData:aDocument];
	return deleteDocumentFetcher;
}

- (void)noteConflicts:(NSString *)patches {
	[conflicts appendString:patches];
}

@end
