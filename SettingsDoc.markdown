## Settings documentation

### compileUnsavedSave

When an unsaved file is compiled, the file will be saved to /tmp/aporia. If this
setting is ``False`` the tab holding the unsaved file will remain in the
unsaved state. Otherwise the tab will transition into the saved state, but will
be marked as temporary.

**Default**: ``True``

### wrapMode

Determines the source view's wrapping mode.

**Possible values**: ``none``, ``char``, ``word``

**Default**: ``none``