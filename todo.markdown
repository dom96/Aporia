# Aporia's Todo list

## Version 0.2.0

* Find all references
* Test on Windows.
* Sort View -> Syntax Highlighting
* keywords.txt -> nimrod.lang
* Output text view limit. OOMed my system because of a lot of output already.
* Go to definition: if forward declarations are present, go to definition should go to the definition not forward declaration.
* Change GUI layout of find bar, add wrap around toggle button etc.
* Search for ⌚, it selects too much with regex.
* Move "Find", "Go to line" etc. to a "Search" menu in the top bar.
* If file is empty, but has a "history" (undo can be performed), user should be asked whether to save.
* Ability to specify main file by creating a simple project.aporia.cfg file in root dir?

    mainFile = main.nim
* Amount of matches when coloring upon highlight.
* Ctrl+/ doesn't work on commented lines with no space after the #
* Syntax Highlighting change is not reflected in the tab's tooltip.
* When invoking suggest, check if cursor is on a "string" tag? Can I determine this?
* Multiple cursors?
* Command bar?
* Separate automatically saved settings by aporia and settings which can be changed by user.

## Other language features
* Ability to change to hard tabs.
* Per file type space vs tab settings and indent width. Also languages should have
  sane defaults.
* Detect what indentation is being used in a file that has been opened.
  * Shortest distance from beginning of line to non-whitespace (or EOL) should
    be the space width.
  * If there are tabs at the beginning of a line then the indentation is tabs.
  * If there are no tabs and there are spaces then spaces.
* Clang-based suggest for C-family languages?

## Miscellaneous

* Make sure suggest dialog gets moved up if we're at the bottom of the screen
* UI shouldn't freeze when opening large files.
* Fix other encodings. (Selection for encodings like in gedit)
* Fix drag and drop of files onto Notebook.
* Find all.
* Different editing modes - html, xml, etc. (These should make editing these particular things easier.)
* Track history of file. When you edit and then undo the file should not be marked as being unsaved.
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
* <del>Instead of project files, each file can have options specified as a comment?
  Like in vim.</del>
  * Evaluate how to handle projects.
* Feature: Select a block of code, split it up into 80 char lines.
  * Should be able to do this on the current line!
* Popular languages listed in View -> Syntax Highlighting?
* <del>When aporia's config file is saved, validate before saving.</del> If incorrect, list errors in Error List?
* List of debug's or echod functions, can be used to easily toggle them when debugging. This will decrease crap in your stdout when you're trying to debug something. And you don't have to hunt down each of your debug functions.
* Color large blocks of indentations.
  * Useful in osproc, the big when defined(windows), it's a bit hard to see when the block ends because it's so big, adding colors may make it easier to see.
* Background indexer of files in the directories of the files that are open. This will allow for quickly searching for files. (Kind of like 't' in github repo pages)
* Separate settings. Add ability to have per-user settings (profiles).
* Use GtkSourceView instead of output text view? This will allow better control of colouring the output from processes.
* http://editorconfig.org/ (Use similar config files for differen language configs?)
* Better diff highlighting? green/red on left with proper highlighting (separate SVs for each file type?) (maybe only for git plugin)
* Add fake space at bottom so that code is not at the bottom of the screen.
* Ability to set a syntax highlighting theme per language.
* Ability to temporarily focus on content, do this by switching to a theme similar to: https://github.com/sindresorhus/focus
* limit tab's title to 20 chars?
* Go to function with autocompletion.
* Being able to go to column with go to line feature
* Force focus the selected tab after initialisation.