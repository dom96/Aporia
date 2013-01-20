# Aporia's Todo list

## Version 0.2.0

* Find all references
* Test on Windows.
* Search & Replace, when clicking replace and a lot of text is scrolled no syntax highlighting occurs.
* "Project" feature, look at existance of file.nimrod.cfg in dir.
* Sort View -> Syntax Highlighting
* When opening a file from Recently opened file. They should be added to the top
  of Recently opened files.
* Fix docs in suggest.
* Temporary file saves.
* keywords.txt -> nimrod.lang
* Output text view limit. OOMed my system because of a lot of output already.
* Go to definition: if forward declarations are present, go to definition should go to the definition not forward declaration.
* Check current tabs language when F5 (etc.) is pressed.
* Change GUI layout of find bar, add wrap around toggle button etc.
* Gdk-CRITICAL **: gdk_window_invalidate_rect_full: assertion `GDK_IS_WINDOW (window)' failed
  * Caused by a GtkSourceView from a tab other than the current one being focused.
  * Use the same strategy as scrolling for making sure that the selected tab gets focused.

## Other language features
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
  * Command bar:
    * Ctrl + Shift + P (or w/e).
    * Type in ``open`` + enter: gives you a list of files in current work dir (as calculated currently)
    * Type in ``open dir`` + enter: gives you a list of files in that dir
    * Type in ``open file`` + enter: opens file obviously.
    * Tab complete should be well thought out.
* c2nim integration. Select text, right click, "convert to Nimrod code using c2nim" option.
* Text macros. I want to be able to with a press of a button start some kind of
  pre-written macro which can do cool things like inspect my clipboard. In the case
  of updating the gtk wrapper, I copy the "gtk_some_object_some_function" I want
  to press Ctrl+B+Something and get a nice wrapped function without the "gtk_"
* Jump to proc/temp/iterator. Ctrl + P ?
* Instead of project files, each file can have options specified as a comment?
  Like in vim.
  * Evaluate how to handle projects.
* Feature: Select a block of code, split it up into 80 char lines.
* Popular languages listed in View -> Syntax Highlighting?
* When aporia's config file is saved, validate before saving. If incorrect, list errors in Error List?
* List of debug's or echod functions, can be used to easily toggle them when debugging. This will decrease crap in your stdout when you're trying to debug something. And you don't have to hunt down each of your debug functions.