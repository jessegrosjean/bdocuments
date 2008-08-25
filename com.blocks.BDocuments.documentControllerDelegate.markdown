Use this extension point to override the default document type that will be created.

## Example Usage

This example comes from WriteRoom. It needs to change the default document type based on the users preference to have plain text or rich text documents created by default. To accomplis that it adds this extension in is Plugin.xml file.

    <extension point="com.blocks.BDocuments.documentControllerDelegate">
        <delegate class="WRDocumentControllerDelegate sharedInstance" />
    </extension>

And then it implements the `WRDocumentControllerDelegate` class like this:

    @implementation WRDocumentControllerDelegate
    
    #pragma mark Class Methods

    + (id)sharedInstance {
        static id sharedInstance = nil;
        if (sharedInstance == nil) {
            sharedInstance = [[self alloc] init];
        }
        return sharedInstance;
    }
    
    #pragma mark Delegate Methods
    
    - (NSString *)defaultType {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:WRDefaultDocumentFormat]) {
            return NSRTFTextDocumentType;
        } else {
            return NSPlainTextDocumentType;
        }
    }
    
    @end