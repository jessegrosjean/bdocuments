//
//  BSyncedDocument.m
//  BDocuments
//
//  Created by Jesse Grosjean on 2/28/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "BCloudDocument.h"
#import "BCloudDocumentsService.h"
#import "BDiffMatchPatch.h"
#import "NSString+SBJSON.h"


@implementation BCloudDocument

- (void)dealloc {
	[openNSDocument release];
	[documentID release];
	[name release];
	[localContent release];
	[localShadowContent release];
	[localShadowContentVersion release];
	[serverVersion release];
	[super dealloc];
}

@synthesize openNSDocument;
@synthesize documentID;
@synthesize name;
@synthesize localContent;
@synthesize localShadowContent;
@synthesize localShadowContentVersion;
@synthesize serverVersion;
@synthesize isScheduledForDeleteOnClient;
@synthesize isDeletedFromServer;
@synthesize isScheduledForInsertOnClient;
@synthesize isInsertedFromServer;

- (BOOL)isInsertedFromServer {
	return self.serverVersion != nil && (self.localShadowContentVersion == nil);
}

- (BOOL)hasLocalEdits {
	return (self.localContent != nil && self.localShadowContent != nil) && ![self.localContent isEqualToString:self.localShadowContent];
}

- (NSDictionary *)localEdits {
	BDiffMatchPatch *diffMatchPatch = [[[BDiffMatchPatch alloc] init] autorelease];
	NSString *patches = [diffMatchPatch patchToText:[diffMatchPatch patchMakeText1:self.localShadowContent text2:self.localContent]];
	return [NSDictionary dictionaryWithObjectsAndKeys:patches, @"patches", self.localShadowContentVersion, @"version", nil];
}

- (BOOL)hasServerEdits {
	return (self.serverVersion != nil && self.localShadowContentVersion != nil) && ![self.serverVersion isEqualToString:self.localShadowContentVersion];
}

- (void)applyServerEdits:(NSDictionary *)edits {
	if ([edits objectForKey:@"version"]) {
		self.serverVersion = [[edits objectForKey:@"version"] description];
		self.localShadowContentVersion = self.serverVersion;
	}
	
	if ([edits objectForKey:@"name"]) {
		self.name = [edits objectForKey:@"name"];
	}
	
	if ([edits objectForKey:@"patches"] != nil && [[edits objectForKey:@"patches"] length] > 0) {
		BDiffMatchPatch *diffMatchPatch = [[[BDiffMatchPatch alloc] init] autorelease];
		NSMutableArray *patches = [diffMatchPatch patchFromText:[edits objectForKey:@"patches"]];
		self.localShadowContent = [[diffMatchPatch patchApply:patches text:localShadowContent] objectAtIndex:0];
	}
}

- (void)scheduleSyncRequest {
	BCloudDocumentsService *syncedDocumentService = [BCloudDocumentsService sharedInstance];

	if (self.isDeletedFromServer) {
		if ([self hasLocalEdits] && !self.isScheduledForDeleteOnClient) {
			syncResponseBehavior = BSyncResponseUpdateLocal;
			[syncedDocumentService POSTServerDocument:self];
		} else {
			[syncedDocumentService deleteLocalDocumentStateForDocumentID:self.documentID];
		}
		return;
	} else if (self.isScheduledForDeleteOnClient) {
		if ([self hasServerEdits]) {
			syncResponseBehavior = BSyncResponseUpdateLocal;
			[syncedDocumentService GETServerDocument:self];
		} else {
			syncResponseBehavior = BSyncResponseDeleteLocal;
			[syncedDocumentService DELETEServerDocument:self];
		}
		return;
	}

	if (self.isScheduledForInsertOnClient) {
		syncResponseBehavior = BSyncResponseUpdateLocal;
		[syncedDocumentService POSTServerDocument:self];
		return;
	} else if (self.isInsertedFromServer) {
		syncResponseBehavior = BSyncResponseUpdateLocal;
		[syncedDocumentService GETServerDocument:self];
		return;
	}
	
	if (self.hasLocalEdits) {
		syncResponseBehavior = BSyncResponseUpdateLocal;
		[syncedDocumentService POSTServerDocumentEdits:self];
	} else if (self.hasServerEdits) {
		syncResponseBehavior = BSyncResponseUpdateLocal;
		[syncedDocumentService GETServerDocumentEdits:self];
	}
}

#pragma mark Sync Callbacks

- (void)processSyncResponse:(NSData *)data {
	BCloudDocumentsService *syncedDocumentService = [BCloudDocumentsService sharedInstance];
	
	if (syncResponseBehavior == BSyncResponseDeleteLocal) {
		[syncedDocumentService deleteLocalDocumentStateForDocumentID:self.documentID];
		return;
	}
	
	NSDictionary *serverDocumentState = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];
	NSString *originalDocumentID = self.documentID;

	if ([serverDocumentState objectForKey:@"id"]) {
		self.documentID = [serverDocumentState objectForKey:@"id"];
	}
	
	if ([serverDocumentState objectForKey:@"version"]) {
		self.serverVersion = [[serverDocumentState objectForKey:@"version"] description];
		self.localShadowContentVersion = self.serverVersion;
	}

	if ([serverDocumentState objectForKey:@"content"]) {
		self.localContent = [serverDocumentState objectForKey:@"content"];
		self.localShadowContent = [serverDocumentState objectForKey:@"content"];
	} else if ([serverDocumentState objectForKey:@"patches"] && [[serverDocumentState objectForKey:@"patches"] length] > 0) {
		BDiffMatchPatch *diffMatchPatch = [[[BDiffMatchPatch alloc] init] autorelease];
		NSMutableArray *patches = [diffMatchPatch patchFromText:[serverDocumentState objectForKey:@"patches"]];
		self.localContent = [[diffMatchPatch patchApply:patches text:localShadowContent] objectAtIndex:0];
		self.localShadowContent = self.localContent;
	}

	if ([serverDocumentState objectForKey:@"name"]) {
		self.name = [serverDocumentState objectForKey:@"name"];
	}
	
	[syncedDocumentService updateLocalDocumentState:self originalDocumentID:originalDocumentID];
	
	if ([serverDocumentState objectForKey:@"failed_patches"]) {
		[syncedDocumentService noteFailedPatches:[serverDocumentState objectForKey:@"failed_patches"]];
	}
}

@end
