Use this extension point to get create create window controllers for a particular document type. This allows a `NSDocument` subclass to be declared in one plugin and an associated `NSWindowController` subclass to be declared in a seprate plugin.

## Examples:

In this configuration example the object returned by `[TPDocumentWindowControllerFactory sharedInstance]` will be given the chance to create new `NSWindowControllers` for each document that's opened by the application. This configuration markup should be added to the Plugin.xml file of the plugin that declares the `TPDocumentWindowControllerFactory` class.

	<extension point="com.blocks.BDocuments.documentDefaultWindowControllersFactory">
        <windowcontrollerFactory factory="TPDocumentWindowControllerFactory sharedInstance" />
    </extension>

`TPDocumentWindowControllerFactory` should conform to the `BDocumentWindowControllerFactory` that's declared in the public header `BDocumentWindowController.h`.