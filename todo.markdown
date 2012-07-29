# Aporia's Todo list

## Version 0.1.3

* Single instance. If an instance of Aporia is already running, and you run aporia with a filename as argument the already running instance should open that file.
* Get rid of echo; change to `echod`.
* Fix key handling issues; KeyRelease/KeyPressed? Ctrl + F5 should work.
* Go to definition, use gtksourceview to know if clicked on identifier.
* Find all references
* Fix drag and drop of files onto Notebook.
* Fix other encodings. (Selection for encoding like in gedit)

## Miscellaneous

* Find all.
* Different editing modes - html, xml, etc. (These should make editing these particular things easier.)
* Track history of file. When you edit and then undo the file should not be marked as being unsaved.
* Use threads when executing the compiler.
* Investigate line and cursor position as well as scrolling when restoring a session.
* Read cmd line args to check for file paths.
* Finish the suggest feature.
* Project management.
* Ability to split vertically into two separate tab views.
* Useful ways to find functions:
  * Find me all functions that return TypeX
  * Find me all functions that take TypeX as first param.
  * Find me all functions that take TypeX as any param.
  * etc.
* Variable inspection in the editor; being able to hover over a variable and see its type
  * This requires better Nimrod compiler integration!
* It should be easier to close the bottom panel. Add an X button.