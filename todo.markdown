# Aporia's Todo list

## Version 0.1.3

* Change Ctrl + L to Ctrl + G
* Get rid of echo; change to `echod`.
* Go to definition, use gtksourceview to know if clicked on identifier.
* Find all references
* Fix drag and drop of files onto Notebook.
* Fix other encodings. (Selection for encodings like in gedit)
* UI shouldn't freeze when opening large files.
* set_smart_home_end
* Make sure suggest dialog gets moved up if we're at the bottom of the screen
* Icons in context menus
* http://mattgraham.github.com/Midnight/ -- Base theme on that code scheme there.
* Save the last opened tab.

## Other language features
* Ability to pick other syntax highlighting
* Ability to change to hard tabs.
* Per file type space vs tab settings and indent width. Also languages should have
  sane defaults.
* Detect what indentation is being used in a file that has been opened.
  * Shortest distance from beginning of line to non-whitespace (or EOL) should
    be the space width.
  * If there are tabs at the beginning of a line then the indentation is tabs.
  * If there are no tabs and there are spaces then spaces.

## Miscellaneous

* When you select a word, the same words should be highlighted in the document.
* Find all.
* Different editing modes - html, xml, etc. (These should make editing these particular things easier.)
* Track history of file. When you edit and then undo the file should not be marked as being unsaved.
* Use threads when executing the compiler.
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
* Syntax highlighting selection
* Detection of files being edited outside of aporia.
* Fix VPaned after that change to win.show().
* docking with http://developer.gnome.org/gdl/
* minimum mode -- look at screenshots dir
* When compiling an unsaved file, make it saved on the frontend. 
  So that when i'm editing it further I can press Ctrl + S without getting angry.
