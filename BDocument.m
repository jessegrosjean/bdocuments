//
//  BDocument.m
//  BDocuments
//
//  Created by Jesse Grosjean on 10/16/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "BDocument.h"
#import "BDocuments.h"
#import "BDocumentWindowController.h"
#import "SyncedDocumentsControllerDelegate.h"
#import "DiffMatchPatch.h"
#import "BDocumentDifferencesWindowController.h"


@implementation BDocument

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		nil]];
}

#pragma mark Document Defaults Repository

static NSMutableArray *documentUserDefautlsArchive = nil;


- (void)updateChangeCount:(NSDocumentChangeType)changeType {
	[super updateChangeCount:changeType];
}


+ (NSString *)documentUserDefaultsArchivePath {
	return [[[NSFileManager defaultManager] processesApplicationSupportFolder] stringByAppendingPathComponent:@"DocumentsUserDefaults.archive"];
}

+ (NSMutableArray *)documentUserDefautlsArchive {
	if (!documentUserDefautlsArchive) {
		documentUserDefautlsArchive = [NSUnarchiver unarchiveObjectWithFile:[self documentUserDefaultsArchivePath]];
		if (!documentUserDefautlsArchive) {
			documentUserDefautlsArchive = [[NSMutableArray alloc] init];
		}
	}
	return documentUserDefautlsArchive;
}

+ (NSDictionary *)loadDocumentUserDefaultsForDocumentURL:(NSURL *)documentURL {
	NSDictionary *documentUserDefaults = [[[self documentUserDefautlsArchive] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"BDocumentsDocumentURL = %@", [documentURL path]]] lastObject];
	if (!documentUserDefaults) {
		documentUserDefaults = [NSDictionary dictionary];
	}
	return documentUserDefaults;
}

+ (BOOL)storeDocumentUserDefaults:(NSDictionary *)documentUserDefaults forDocumentURL:(NSURL *)documentURL {
	if (!documentURL) return NO;
	if (!documentUserDefaults) return NO;
	
	NSDictionary *oldDocumentUserDefaults = [[[self documentUserDefautlsArchive] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"BDocumentsDocumentURL = %@", [documentURL path]]] lastObject];
	if (oldDocumentUserDefaults) {
		[documentUserDefautlsArchive removeObject:oldDocumentUserDefaults];
	}
	
	NSMutableDictionary *newDocumentUserDefaults = [documentUserDefaults mutableCopy];
	[newDocumentUserDefaults setObject:[documentURL path] forKey:@"BDocumentsDocumentURL"];
	[documentUserDefautlsArchive addObject:newDocumentUserDefaults];
	
	return YES;
}

+ (BOOL)synchronizeDocumentUserDefaultsRepository {
	[[NSNotificationCenter defaultCenter] postNotificationName:BDocumentUserDefaultsWillSynchronizeNotification object:self];
	
	NSInteger count = [[self documentUserDefautlsArchive] count];
	NSInteger max = 100;
	
	if (count > max) {
		[documentUserDefautlsArchive removeObjectsInRange:NSMakeRange(0, count - max)]; // keep newer user infos at end of array
	}
	
	if (![NSArchiver archiveRootObject:documentUserDefautlsArchive toFile:[self documentUserDefaultsArchivePath]]) {
		BLogWarning(@"failed to save documentUserDefautlsArchive");
		return NO;
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:BDocumentUserDefaultsDidSynchronizeNotification object:self];
	
	return YES;
}

#pragma mark awakeFromNib-like methods

- (void)makeWindowControllers {
	// First make sure to load plugins containing all window controller factories so that NSClassFromString(className) will work bellow for saved window controllers.
	for (BPlugin *each in [[[BExtensionRegistry sharedInstance] configurationElementsFor:@"com.blocks.BDocuments.documentDefaultWindowControllersFactory"] valueForKey:@"plugin"]) {
		NSError *error = nil;
		if (![each loadAndReturnError:&error]) {
			[NSApp presentError:error];
		}
	}

	NSDictionary *documentWindowControllersState = [self documentUserDefaultForKey:BDocumentsWindowControllersDefaultsKey];
	
	for (NSString *eachKey in [documentWindowControllersState keyEnumerator]) {
		NSDictionary *windowControllerState = [documentWindowControllersState objectForKey:eachKey];
		NSString *className = [windowControllerState objectForKey:@"class"];
		if (className) {
			Class class = NSClassFromString(className);
			NSWindowController *windowController = [[class alloc] initWithWindowControllerUserDefaultsKey:eachKey];
			if (windowController) {
				[self addWindowController:windowController];
			}
		}
	}
	
	if ([[self windowControllers] count] == 0) {
		for (BConfigurationElement *each in [[BExtensionRegistry sharedInstance] configurationElementsFor:@"com.blocks.BDocuments.documentDefaultWindowControllersFactory"]) {
			id <BDocumentWindowControllerFactory> windowControllerFactory = [each createExecutableExtensionFromAttribute:@"factory" conformingToClass:nil conformingToProtocol:@protocol(BDocumentWindowControllerFactory) respondingToSelectors:nil];
			NSWindowController *windowController = [windowControllerFactory createDocumentWindowControllerForDocument:self];
			if (windowController) {
				[self addWindowController:windowController];
			}
		}
	}
}

- (void)removeWindowController:(BDocumentWindowController *)windowController {
	NSMutableDictionary *documentWindowControllersState = [self documentUserDefaultForKey:BDocumentsWindowControllersDefaultsKey];
	if ([documentWindowControllersState count] > 1) {
		[documentWindowControllersState removeObjectForKey:[windowController windowControllerUserDefaultsKey]];
	}
	[super removeWindowController:windowController];
}

#pragma mark Printing

- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings error:(NSError **)outError {
    if ([[self windowControllers] count] == 0) [self makeWindowControllers];
	
	id windowController = [[self windowControllers] lastObject];
	
	if ([windowController respondsToSelector:@selector(printOperationWithSettings:error:)]) {
		return [windowController printOperationWithSettings:printSettings error:outError];
	}
	
	return nil;
}

#pragma mark Document User Defaults

- (NSDictionary *)defaultDocumentUserDefaults {
	return [NSDictionary dictionary];
}

- (NSDictionary *)documentUserDefaults {
	if (!documentUserDefaults) {
		documentUserDefaults = [[self defaultDocumentUserDefaults] mutableCopy];
	}
	return documentUserDefaults;
}

- (id)documentUserDefaultForKey:(NSString *)key {
	return [[self documentUserDefaults] objectForKey:key];
}

- (void)setDocumentUserDefault:(id)documentUserDefault forKey:(NSString *)key {
	if (documentUserDefault) {
		if ([documentUserDefault conformsToProtocol:@protocol(NSCoding)]) {
			[(id)[self documentUserDefaults] setObject:documentUserDefault forKey:key];
		} else {
			BLogWarning([NSString stringWithFormat:@"%@ cannot be set as document user default because it does not conform to coding protocol", documentUserDefault], nil);
		}
	} else {
		[documentUserDefaults removeObjectForKey:key];
	}
}

- (void)addDocumentUserDefaultsFromDictionary:(NSDictionary *)newDocumentUserDefaults {
	for (NSString *eachKey in [newDocumentUserDefaults keyEnumerator]) {
		[self setDocumentUserDefault:[newDocumentUserDefaults objectForKey:eachKey] forKey:eachKey];
	}
}

- (void)close {
	[BDocument storeDocumentUserDefaults:[self documentUserDefaults] forDocumentURL:[self fileURL]];
	[super close];
}

#pragma mark ODB Editor Suite support

@synthesize fromExternal;
@synthesize externalSender;
@synthesize externalToken;

- (NSString *)displayName {
	if (fromExternal && externalDisplayName != nil) {
		return externalDisplayName;
	} else if (fromSyncedDocument) {
		return [SyncedDocumentsControllerDelegate displayNameForSyncedDocument:[self fileURL]];
	}
	return [super displayName];
}

#pragma mark Reading and Writing

- (IBAction)showUnsavedChanges:(id)sender {
	NSWindowController *windowController = [[self windowControllers] lastObject];
	NSWindow *window = [windowController window];
	NSURL *fileURL = [self fileURL];
	NSString *messageText = nil;
	NSString *informativeText = @"";
	
	if (fileURL) {
		NSString *unsavedText = [self textContents];
		NSString *savedText = [self savedTextContents:nil];
		
		if ([savedText isEqualToString:unsavedText]) {
			messageText = BLocalizedString(@"Your document has no unsaved changes.", nil);
			informativeText = BLocalizedString(@"The content of your open document is exactly the same as the content that is saved on disk.", nil);
		} else {
			BDocumentDifferencesWindowController *differencesWindowController = [[BDocumentDifferencesWindowController alloc] initWithText1:savedText text2:unsavedText];
			[differencesWindowController setMessageText:BLocalizedString(@"These are your unsaved changes.", nil)];
			[NSApp beginSheet:[differencesWindowController window] modalForWindow:window modalDelegate:self didEndSelector:@selector(showUnsavedChangesSheetDidEnd:returnCode:contextInfo:) contextInfo:nil];
			return;
		}
	} else {
		messageText = BLocalizedString(@"Your document has not been saved.", nil);
		informativeText = BLocalizedString(@"You must first save your document before you can compare it to the content that is saved on disk.", nil);
	}
	
	NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:informativeText];
	[alert beginSheetModalForWindow:window modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

- (void)showUnsavedChangesSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	[sheet orderOut:self];
}

- (NSString *)textContentsFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
	NSMutableString *string = [[NSMutableString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (string) {
		NSString *windowsLineEnding = [[NSString alloc] initWithFormat:@"%C%C", 0x000D, 0x000A];
		NSString *macLineEnding = [[NSString alloc] initWithFormat:@"%C", 0x000D];
		[string replaceOccurrencesOfString:windowsLineEnding withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, [string length])];
		[string replaceOccurrencesOfString:macLineEnding withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, [string length])];
		return string;
	} else {
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  BLocalizedString(@"The file is not in the right format.", nil), NSLocalizedDescriptionKey,
								  BLocalizedString(@"The file might be corrupted, truncated, or in a different format than you expect.", nil), NSLocalizedRecoverySuggestionErrorKey,
								  BLocalizedString(@"The file is not in the right format.", nil), NSLocalizedFailureReasonErrorKey,
								  nil];
		
		*outError = [[NSError alloc] initWithDomain:@"com.hogbaysoftware.taskpaper.TPDocument" code:1 userInfo:userInfo]; // Why does none of this error info get displayed?
		
		return nil;
	}
}

- (NSString *)savedTextContents:(NSError **)error {
	return [self textContentsFromData:[NSData dataWithContentsOfURL:[self fileURL]] ofType:[self fileType] error:error];
}

- (NSString *)textContents {
	return nil;
}

- (void)setTextContents:(NSString *)newString {
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
	NSString *string = [self textContentsFromData:data ofType:typeName error:outError];
	
	if (string) {
		[[self undoManager] disableUndoRegistration];
		[self setTextContents:string];
		[[self undoManager] enableUndoRegistration];
		[self addDocumentUserDefaultsFromDictionary:[BDocument loadDocumentUserDefaultsForDocumentURL:[self fileURL]]];			
		lastKnownTextContentsOnDisk = string;
		return YES;
	} else {
		return NO;
	}
}

- (void)setFileURL:(NSURL *)absoluteURL {
	[super setFileURL:absoluteURL];
	fromSyncedDocument = [SyncedDocumentsControllerDelegate isSyncedDocumentURL:[self fileURL]];
}

- (NSInteger)fileHFSTypeCode {
	[NSException raise:@"Subclass must overide" format:@""];
	return 0;
}

- (NSInteger)fileHFSCreatorCode {
	[NSException raise:@"Subclass must overide" format:@""];
	return 0;
}

- (NSDictionary *)fileAttributesToWriteToFile:(NSString *)fullDocumentPath ofType:(NSString *)docType saveOperation:(NSSaveOperationType)saveOperationType {
	NSMutableDictionary *attributes = [[super fileAttributesToWriteToFile:fullDocumentPath ofType:docType saveOperation:saveOperationType] mutableCopy];
	[attributes setObject:[NSNumber numberWithUnsignedInteger:[self fileHFSTypeCode]] forKey:NSFileHFSTypeCode];
	[attributes setObject:[NSNumber numberWithUnsignedInteger:[self fileHFSCreatorCode]] forKey:NSFileHFSCreatorCode];
	return attributes;
}

@synthesize fromSyncedDocument;

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)saveOperation originalContentsURL:(NSURL *)absoluteOriginalContentsURL error:(NSError **)outError {
	NSString *textContents = [self textContents];

	if ([textContents writeToURL:absoluteURL atomically:YES encoding:NSUTF8StringEncoding error:outError]) {
		if (saveOperation == NSSaveOperation || saveOperation == NSSaveAsOperation) {
			[BDocument storeDocumentUserDefaults:[self documentUserDefaults] forDocumentURL:[self fileURL]];
			lastKnownTextContentsOnDisk = textContents;
		}
		return YES;
	}
	
	return NO;
}

- (void)BDocument_checkForModificationOfFileOnDisk {
	NSDate *knownFileModificationDate = [self fileModificationDate];
	if (knownFileModificationDate) {
		NSDate *actualFileModificationDate = [[[NSFileManager defaultManager] fileAttributesAtPath:[[self fileURL] path] traverseLink:YES] fileModificationDate];
		
		if ([knownFileModificationDate isLessThan:actualFileModificationDate]) {
			NSError *error = nil;
			NSString *savedTextContents = [self savedTextContents:&error];
			if (savedTextContents) {
				DiffMatchPatch *dmp = [[DiffMatchPatch alloc] init];
				NSMutableArray *patches = [dmp patchMakeText1:lastKnownTextContentsOnDisk text2:savedTextContents];
				if ([patches count] > 0) {
					NSArray *patchResults = [dmp patchApply:patches text:[self textContents]];
					NSString *patchedDocumentText = [patchResults objectAtIndex:0];
					[self setTextContents:patchedDocumentText];
					
					NSUInteger index = 0;
					NSMutableArray *failedDiffs = [NSMutableArray array];
					for (NSNumber *each in [patchResults objectAtIndex:1]) {
						if ([each boolValue] == NO) {
							[failedDiffs addObjectsFromArray:[[patches objectAtIndex:index] diffs]];
						}
						index++;
					}
					
					if ([failedDiffs count] > 0) {
						NSWindow *window = [[[self windowControllers] lastObject] window];
						BDocumentDifferencesWindowController *differencesWindowController = [[BDocumentDifferencesWindowController alloc] initWithDiffs:failedDiffs];
						[differencesWindowController setMessageText:BLocalizedString(@"This document's file has been changed by another application. These changes could not be merged back into your open document.", nil)];
						[NSApp beginSheet:[differencesWindowController window] modalForWindow:window modalDelegate:self didEndSelector:@selector(showMergeFailuresSheetDidEnd:returnCode:contextInfo:) contextInfo:nil];
					}
				}
				
				[self setFileModificationDate:actualFileModificationDate];
			}
		}
	}
}

- (void)showMergeFailuresSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	[sheet orderOut:self];
}						


@end

@implementation NSDocument (BDocumentAdditions)

- (void)checkForModificationOfFileOnDisk {
	if ([self respondsToSelector:@selector(BDocument_checkForModificationOfFileOnDisk)]) {
		[self performSelector:@selector(BDocument_checkForModificationOfFileOnDisk)];
	}
}

@end

@implementation NSDocument (BDocumentMethodReplacements)

+ (void)load {
    if (self == [NSDocument class]) {
		[NSDocument replaceMethod:@selector(_handleDocumentFileChanges:) withMethod:@selector(BDocument_handleDocumentFileChanges:)];
    }
}

- (void)BDocument_handleDocumentFileChanges:(id)arg {
	if (![[NSFileManager defaultManager] fileExistsAtPath:[[self fileURL] path]]) {
		[self BDocument_handleDocumentFileChanges:arg]; // Only allow AppKit to track moved files if the original file path has been deleted.
	}
}

@end


NSString *BDocumentUserDefaultsWillSynchronizeNotification = @"BDocumentUserDefaultsWillSynchronizeNotification";
NSString *BDocumentUserDefaultsDidSynchronizeNotification = @"BDocumentUserDefaultsDidSynchronizeNotification";