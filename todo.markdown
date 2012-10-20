# Aporia's Todo list

## Version 0.1.3

* Find all references
* Save the last opened tab.
* Test on Windows.
* Language list in menu.
* When you select a word, the same words in the doc should be highlighted.
* Font settings for output text view.
* Search & Replace, when clicking replace and a lot of text is scrolled no syntax highlighting occurs.

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

* Make sure suggest dialog gets moved up if we're at the bottom of the screen
* UI shouldn't freeze when opening large files.
* Fix other encodings. (Selection for encodings like in gedit)
* Fix drag and drop of files onto Notebook.
* Find all.
* Different editing modes - html, xml, etc. (These should make editing these particular things easier.)
* Track history of file. When you edit and then undo the file should not be marked as being unsaved.
* Use threads when executing the compiler.
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
* Detection of files being edited outside of aporia.
* Fix VPaned after that change to win.show().
* docking with http://developer.gnome.org/gdl/
* minimum mode -- look at screenshots dir
* When compiling an unsaved file, make it saved on the frontend. 
  So that when i'm editing it further I can press Ctrl + S without getting angry.
* If search term is misspelled, try to find something close to it and color
  the textbox orange but do go to it.
* Ctrl+Shift up/down should move the current line up or down.
* Commands?
* Make the find bar text boxes span the whole find bar.
* c2nim integration. Select text, right click, "convert to Nimrod code using c2nim" option.
* Text macros. I want to be able to with a press of a button start some kind of
  pre-written macro which can do cool things like inspect my clipboard. In the case
  of updating the gtk wrapper, I copy the "gtk_some_object_some_function" I want
  to press Ctrl+B+Something and get a nice wrapped function without the "gtk_"
* Jump to proc/temp/iterator. Ctrl + P ?