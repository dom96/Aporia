Version 0.2
=============

* Tabs can now be reordered.
* Close button can now only be shown on the selected tab. (This is configurable)
* Error list.
* Many bug fixes for handling of processes.
* Aporia is now a single instance application. This means you can easily
  open documents from the file manager and it will open in the same aporia window.
  (Compile with ``-d:noSingleInstance`` to disable this behaviour)
* Scrolling when restoring a session **finally** works.
* Added 'piekno' and 'yumbum' (Created by fowl) color schemes.
* 'piekno' is now the default color scheme.
* Pragmas can now be colored using the "nimrod:pragma" style name.
* Whole blocks and lines of code can now be commented using Ctrl + /.
* Tabs and two consecutive underscores are now highlighted as errors when using
the Nimrod syntax highlighter.
* Recent file list in File menu.
* Fixed a bug where double clicking on the tabs/scrollbar caused a new tab to
  be opened.
* Opening documents which are non-utf8 now works, aporia prompts the user for
  the encoding.
* Improved status bar; when text is selected the status bar now reports the
  amount of lines/characters that are selected.
* Fixed a bug where Save As did not properly change the syntax highlighting of
  the file.
* Syntax highlighting can now be changed by going to View -> Syntax Highlighting.
* Aporia's config file can now be opened in Aporia easily through the Edit menu.
* Suggest and Go to definition is now executed asynchronously.
* Fixed a bug where Style insensitive search does not find tabulators.
* Fixed a bug where searching backwards may skip to the end of the file instead
  of matching a term at the top of the file.
* When searching, all occurrences in the document of your search will now be
  highlighted.
* When you select text all occurrences of the selected text will now be highlighted.