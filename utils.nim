#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, gtksourceview, osproc, streams, AboutDialog, asyncio

type
  TSettings* = object
    search*: TSearchEnum # Search mode.
    wrapAround*: bool # Whether to wrap the search around.
    
    font*: string # font used by the sourceview
    colorSchemeID*: string # color scheme used by the sourceview
    indentWidth*: int32 # how many spaces used for indenting code (in sourceview)
    showLineNumbers*: bool # whether to show line numbers in the sourceview
    highlightMatchingBrackets*: bool # whether to highlight matching brackets
    rightMargin*: bool # Whether to show the right margin
    highlightCurrentLine*: bool # Whether to highlight the current line
    autoIndent*: bool

    winMaximized*: bool # Whether the MainWindow is maximized on startup
    VPanedPos*: int32 # Position of the VPaned, which splits
                      # the sourceViewTabs and bottomPanelTabs
    winWidth*, winHeight*: int32 # The size of the window.
    
    toolBarVisible*: bool # Whether the top panel is shown
    bottomPanelVisible*: bool # Whether the bottom panel is shown
    suggestFeature*: bool # Whether the suggest feature is enabled
    
    nimrodCmd*: string  # command template to use to exec the Nimrod compiler
    customCmd1*: string # command template to use to exec a custom command
    customCmd2*: string # command template to use to exec a custom command
    customCmd3*: string # command template to use to exec a custom command
    
    recentlyOpenedFiles*: seq[string] # paths of recently opened files
    singleInstancePort*: int32 # Port used for listening socket to get filepaths
    showCloseOnAllTabs*: bool # Whether to show a close btn on all tabs.
    
    
  MainWin* = object
    # Widgets
    w*: gtk2.PWindow
    suggest*: TSuggestDialog
    nimLang*: PSourceLanguage
    scheme*: PSourceStyleScheme # color scheme the sourceview is meant to use
    SourceViewTabs*: PNotebook # Tabs which hold the sourceView
    bottomBar*: PStatusBar 
    bottomProgress*: PProgressBar
    
    toolBar*: PToolBar # FIXME: should be notebook?
    bottomPanelTabs*: PNotebook
    outputTextView*: PTextView
    errorListWidget*: PTreeView
    
    findBar*: PHBox # findBar
    findEntry*: PEntry
    replaceEntry*: PEntry
    replaceLabel*: PLabel
    replaceBtn*: PButton
    replaceAllBtn*: PButton
    
    goLineBar*: TGoLineBar
    
    FileMenu*: PMenu
    
    viewToolBarMenuItem*: PMenuItem # view menu
    viewBottomPanelMenuItem*: PMenuItem # view menu

    Tabs*: seq[Tab] # Other
    
    tempStuff*: Temp # Just things to remember. TODO: Rename to `other' ?
    
    settings*: TSettings
    oneInstSock*: PAsyncSocket
    IODispatcher*: PDispatcher

  TSuggestDialog* = object
    dialog*: gtk2.PWindow
    treeView*: PTreeView
    items*: seq[TSuggestItem] ## Visible items (In the treeview)
    allItems*: seq[TSuggestItem] ## All items found in current context.
    shown*: bool
    currentFilter*: string
    tooltip*: PWindow
    tooltipLabel*: PLabel
  
  TExecMode* = enum
    ExecNone, ExecNimrod, ExecRun, ExecCustom
  
  TExecThrTaskType* = enum
    ThrRun, ThrStop
  TExecThrTask* = object
    case typ*: TExecThrTaskType
    of ThrRun:
      command*: string
    of ThrStop: nil
  
  TExecThrEventType* = enum
    EvStarted, EvRecv, EvStopped
  TExecThrEvent* = object
    case typ*: TExecThrEventType
    of EvStarted:
      p*: PProcess
    of EvRecv:
      line*: string
    of EvStopped:
      exitCode*: int
  
  Temp = object
    lastSaveDir*: string # Last saved directory/last active directory
    stopSBUpdates*: Bool
    
    execMode*: TExecMode
    ifSuccess*: string
    compileSuccess*: bool
    execThread*: TThread[void]
    execProcess*: PProcess
    idleFuncId*: int32
    lastProgressPulse*: float
    errorMsgStarted*: bool
    compilationErrorBuffer*: string # holds error msg if it spans multiple lines.
    errorList*: seq[TError]

    recentFileMenuItems*: seq[PMenuItem] # Menu items to be destroyed.
    lastTab*: int # For reordering tabs, the last tab that was selected.

  Tab* = object
    buffer*: PSourceBuffer
    sourceView*: PSourceView
    label*: PLabel
    closeBtn*: PButton # This is so that the close btn is only shown on selected tabs.
    saved*: bool
    filename*: string
    
    
  TSuggestItem* = object
    nodeType*, name*, nimType*, file*, nmName*: string
    line*, col*: int32
  
  TSearchEnum* = enum
    SearchCaseSens, SearchCaseInsens, SearchStyleInsens, SearchRegex, SearchPeg

  TGoLineBar* = object
    bar*: PHBox
    entry*: PEntry

  TErrorType* = enum
    TETError, TETWarning

  TError* = object
    kind*: TErrorType
    desc*, file*, line*, column*: string

# -- Debug
proc echod*[T](s: openarray[T]) =
  when not defined(release):
    for i in items(s): stdout.write(i)
    echo()


# -- Useful TextView functions.

proc createColor*(textView: PTextView, name, color: string): PTextTag =
  # This function makes sure that the color is created only once.
  var tagTable = textView.getBuffer().getTagTable()
  result = tagTable.tableLookup(name)
  if result == nil:
    result = textView.getBuffer().createTag(name, "foreground", color, nil)

proc addText*(textView: PTextView, text: string,
             colorTag: PTextTag = nil, scroll: bool = true) =
  if text != nil:
    var iter: TTextIter
    textView.getBuffer().getEndIter(addr(iter))

    if colorTag == nil:
      textView.getBuffer().insert(addr(iter), text, int32(len(text)))
    else:
      textView.getBuffer().insertWithTags(addr(iter), text, len(text).int32, colorTag,
                                          nil)
    if scroll:
      var endMark = textView.getBuffer().getMark("endMark")
      # Yay! With the use of marks; scrolling always occurs!
      textView.scrollToMark(endMark, 0.0, False, 0.0, 1.0)

proc scrollToInsert*(win: var MainWin, tabIndex: int32 = -1) =
  var current = win.SourceViewTabs.getCurrentPage()
  if tabIndex != -1: current = tabIndex

  var mark = win.Tabs[current].buffer.getInsert()
  win.Tabs[current].sourceView.scrollToMark(mark, 0.0, False, 0.0, 0.0)

# -- Useful TreeView function
proc createTextColumn*(tv: PTreeView, title: string, column: int,
                      expand = false, resizable = true) =
  ## Creates a new Text column.
  var c = TreeViewColumnNew()
  var renderer = cellRendererTextNew()
  c.columnSetTitle(title)
  c.columnPackStart(renderer, expand)
  c.columnSetExpand(expand)
  c.columnSetResizable(resizable)
  c.columnSetAttributes(renderer, "text", column, nil)
  assert tv.appendColumn(c) == column+1

