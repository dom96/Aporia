#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, gtksourceview, glib2, osproc, streams, AboutDialog, asyncio, strutils
import tables, os, dialogs, pegs

from CustomStatusBar import PCustomStatusBar, TStatusID
from gdk2 import TRectangle, intersect

type
  TSettings* = object
    search*: TSearchEnum # Search mode.
    wrapAround*: bool # Whether to wrap the search around.
    selectHighlightAll*: bool # Whether to highlight all occurrences upon selection
    searchHighlightAll*: bool # Whether to highlight all occurrences of the currently searched text
    
    font*: string # font used by the sourceview
    outputFont*: string # font used by the output textview
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
    compileUnsavedSave*: bool # Whether compiling unsaved files will make them appear saved in the front end.
    
    nimrodCmd*: string  # command template to use to exec the Nimrod compiler
    customCmd1*: string # command template to use to exec a custom command
    customCmd2*: string # command template to use to exec a custom command
    customCmd3*: string # command template to use to exec a custom command
    
    recentlyOpenedFiles*: seq[string] # paths of recently opened files
    singleInstancePort*: int32 # Port used for listening socket to get filepaths
    showCloseOnAllTabs*: bool # Whether to show a close btn on all tabs.
    lastSelectedTab*: string # The tab filename that was selected when aporia was last closed.

    nimrodPath*: string
    
  MainWin* = object
    # Widgets
    w*: gtk2.PWindow
    suggest*: TSuggestDialog
    nimLang*: PSourceLanguage
    scheme*: PSourceStyleScheme # color scheme the sourceview is meant to use
    SourceViewTabs*: PNotebook # Tabs which hold the sourceView
    statusBar*: PCustomStatusBar
    
    infobar*: PInfoBar ## For encoding selection
    
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
    gotAll*: bool # Whether all suggest items have been read.
    currentFilter*: string
    tooltip*: PWindow
    tooltipLabel*: PLabel
  
  TExecMode* = enum
    ExecNimrod, ExecRun, ExecCustom
  
  PExecOptions* = ref TExecOptions
  TExecOptions* = object
    command*: string
    workDir*: string
    mode*: TExecMode
    output*: bool
    onLine*: proc (win: var MainWin, opts: PExecOptions, line: string) {.closure.}
    onExit*: proc (win: var MainWin, opts: PExecOptions, exitcode: int) {.closure.}
    runAfterSuccess*: bool # If true, ``runAfter`` will only be ran on success.
    runAfter*: PExecOptions
  
  TExecThrTaskType* = enum
    ThrRun, ThrStop
  TExecThrTask* = object
    case typ*: TExecThrTaskType
    of ThrRun:
      command*: string
      workDir*: string
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
    
    currentExec*: PExecOptions # nil if nothing is being executed.
    compileSuccess*: bool
    execThread*: TThread[void]
    execProcess*: PProcess
    idleFuncId*: int32
    progressStatusID*: TStatusID
    lastProgressPulse*: float
    errorMsgStarted*: bool
    compilationErrorBuffer*: string # holds error msg if it spans multiple lines.
    errorList*: seq[TError]
    gotDefinition*: bool

    recentFileMenuItems*: seq[PMenuItem] # Menu items to be destroyed.
    lastTab*: int # For reordering tabs, the last tab that was selected.
    commentSyntax*: tuple[line: string, blockStart: string, blockEnd: string]
    pendingFilename*: string # Filename which could not be opened due to encoding.
    plMenuItems*: tables.TTable[string, tuple[mi: PCheckMenuItem, id: string]]
    stopPLToggle*: bool
    currentToggledLang*: string # ID of the currently active pl

  Tab* = object
    buffer*: PSourceBuffer
    sourceView*: PSourceView
    label*: PLabel
    closeBtn*: PButton # This is so that the close btn is only shown on selected tabs.
    saved*: bool
    filename*: string
    highlighted*: THighlightAll
    
  TSuggestItem* = object
    nodeType*, name*, nimType*, file*, nmName*, docs*: string
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

  TEncodingsAvailable* = enum
    UTF8 = "UTF-8", ISO88591 = "ISO-8859-1", GB2312 = "GB2312",
    Windows1251 = "Windows-1251", UTF16BE = "UTF-16BE", UTF16LE = "UTF-16LE"

  THighlightAll* = object
    isHighlighted*: bool
    text*: string # What is currently being highlighted in this tab
    forSearch*: bool # Whether highlightedText is done as a result of a search.
    idleID*: int32

# -- Debug
proc echod*(s: varargs[string, `$`]) =
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

proc removeTag*(buffer: PTextBuffer, name: string): bool =
  ## Removes a TextTag from ``buffer`` with the name of ``name``.
  ## Returns whether tag was removed.
  var tagTable = buffer.getTagTable()
  var tag = tagTable.tableLookup(name)
  if tag == nil: return false
  tagTable.tableRemove(tag)
  return true

proc getTag*(buffer: PTextBuffer, name: string): PTextTag =
  ## Gets tag with ``name``. Return nil if it does not exist.
  return buffer.getTagTable().tableLookup(name)

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

proc forceScrollToInsert*(win: var MainWin, tabIndex: int32 = -1) =
  ## Uses an idle proc to make sure that the SourceView scrolls. This is quite
  ## effective when the sourceview has just been initialised.
  var current = -1
  if tabIndex != -1: current = tabIndex
  else: current = win.SourceViewTabs.getCurrentPage()

  var mark = win.Tabs[current].buffer.getInsert()
  win.Tabs[current].sourceView.scrollToMark(mark, 0.25, False, 0.0, 0.0)
  
  # TODO: What if I remove the tab, while this is happening, segfault because
  # sourceview is gone? The likelihood of this happening is probably very unlikely
  # though.
  
  proc idleConfirmScroll(sv: PSourceView): bool {.cdecl.} =
    result = false
    
    var buff = sv.getBuffer()
    var insertMark = buff.getInsert()
    var insertIter: TTextIter
    buff.getIterAtMark(addr(insertIter), insertMark)
    var insertLoc: TRectangle
    sv.getIterLocation(addr(insertIter), addr(insertLoc))
    
    var rect: TRectangle
    sv.getVisibleRect(addr(rect))
    
    # Now check whether insert iter is inside the visible rect.
    # Width has to be higher than 0
    if insertLoc.width <= 0: insertLoc.width = 1
    let inside = intersect(addr(rect), addr(insertLoc), nil)
    if not inside:
      sv.scrollToMark(insertMark, 0.25, False, 0.0, 0.0)
      return true
  
  discard gIdleAdd(idleConfirmScroll, win.Tabs[current].sourceview)

proc scrollToInsert*(win: var MainWin, tabIndex: int32 = -1) =
  var current = -1
  if tabIndex != -1: current = tabIndex
  else: current = win.SourceViewTabs.getCurrentPage()

  var mark = win.Tabs[current].buffer.getInsert()
  win.Tabs[current].sourceView.scrollToMark(mark, 0.25, False, 0.0, 0.0)

proc findTab*(win: var MainWin, filename: string, absolute: bool = true): int =
  for i in 0..win.Tabs.len()-1:
    if absolute:
      if win.Tabs[i].filename == filename: 
        return i
    else:
      if win.Tabs[i].filename.extractFilename == filename:
        return i 
      elif win.tabs[i].filename == "" and filename == ("a" & $i & ".nim"):
        return i

  return -1

# -- TreeIter functions
proc moveToEndLine*(iter: PTextIter) =
  ## Moves ``iter`` to the end of the current line.
  ## This guarantees that the iter will stay on the same line.
  ## Unlike gtk2's ``forwardToLineEnd``
  var currentLine = iter.getLine()
  iter.setLineOffset(0)
  discard iter.forwardToLineEnd()
  if currentLine != iter.getLine():
    # This will only happen if iter is on an empty line. We can safely return
    # to its first char, because there is no more chars on that line.
    iter.setLine(currentLine)

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
  doAssert tv.appendColumn(c) == column+1

# -- Useful ListStore functions
proc add*(ls: PListStore, val: String, col = 0) =
  var iter: TTreeIter
  ls.append(addr(iter))
  ls.set(addr(iter), col, val, -1)

# -- Useful Menu functions
proc createAccelMenuItem*(toolsMenu: PMenu, accGroup: PAccelGroup, 
                         label: string, acc: gint,
                         action: proc (i: PMenuItem, p: pointer) {.cdecl.},
                         mask: gint = 0,
                         stockid: string = "") = 
  var result: PMenuItem
  if stockid != "":
    result = imageMenuItemNewFromStock(stockid, nil)
  else:
    result = menu_item_new(label)
  
  result.addAccelerator("activate", accGroup, acc, mask, ACCEL_VISIBLE)
  ToolsMenu.append(result)
  show(result)
  discard signal_connect(result, "activate", SIGNAL_FUNC(action), nil)

proc createMenuItem*(menu: PMenu, label: string, 
                     action: proc (i: PMenuItem, p: pointer) {.cdecl.}) =
  var result = menuItemNew(label)
  menu.append(result)
  show(result)
  discard signalConnect(result, "activate", SIGNALFUNC(action), nil)

proc createImageMenuItem*(menu: PMenu, stockid: string,
                          action: proc (i: PMenuItem, p: pointer) {.cdecl.}) =
  var result = imageMenuItemNewFromStock(stockid, nil)
  menu.append(result)
  show(result)
  discard signalConnect(result, "activate", SIGNALFUNC(action), nil)

proc createSeparator*(menu: PMenu) =
  var sep = separator_menu_item_new()
  menu.append(sep)
  sep.show()

# -- Window functions
proc forcePresent*(w: PWindow) =
  w.present()
  
  proc idleConfirmPresent(y: PWindow): bool {.cdecl.} =
    y.present()
    result = not y.isActive()
  
  if not w.isActive():
    discard gIdleAdd(idleConfirmPresent, w)

# -- Others

proc getCurrentTab*(win: var MainWin): int =
  result = win.sourceViewTabs.GetCurrentPage()
  if result < 0:
    result = 0

proc findProjectFile*(directory: string): tuple[projectFile, projectCfg: string] =
  ## Finds the .nim project file in ``directory``.
  # Find project file
  var configFiles: seq[string] = @[]
  for cfgFile in walkFiles(directory / "*.nimrod.cfg"):
    configFiles.add(cfgFile)
  let projectCfgFile = if configFiles.len != 1: "" else: configFiles[0]
  var projectFile = if projectCfgFile != "": projectCfgFile[0 .. -8] else: ""
  if not existsFile(projectFile):
    # check for file.nimrod
    if not existsFile(projectFile & "rod"):
      projectFile = ""
    else:
      projectFile = projectFile & "rod"
  return (projectFile, projectCfgFile)

proc isTemporary*(t: Tab): bool =
  ## Determines whether ``t`` is saved in /tmp
  return t.filename.startsWith(getTempDir())

# -- Programming Language handling
proc getCurrentLanguage*(win: var MainWin, pageNum: int = -1): string =
  ## Returns the current language ID.
  ##
  ## ``""`` is returned if there is no syntax highlighting for the current doc.
  var currentPage = pageNum
  if currentPage == -1:
    currentPage = win.getCurrentTab()
  var isHighlighted = win.Tabs[currentPage].buffer.getHighlightSyntax()
  if isHighlighted:
    var SourceLanguage = win.Tabs[currentPage].buffer.getLanguage()
    if SourceLanguage == nil: return ""
    return $sourceLanguage.getID()
  else:
    return ""

proc getLanguageName*(win: var MainWin, buffer: PSourceBuffer): string =
  ## Returns the language name of ``buffer``.
  ##
  ## If there is no syntax highlighting for the current tab ``"Plain Text"`` is
  ## returned.
  var isHighlighted = buffer.getHighlightSyntax()
  if isHighlighted:
    var SourceLanguage = buffer.getLanguage()
    if SourceLanguage == nil: return "Plain Text"
    return $sourceLanguage.getName()
  else:
    return "Plain Text"

proc getLanguageName*(win: var MainWin, pageNum: int = -1): string =
  ## Returns the language name of the ``pageNum`` tab.
  var currentPage = pageNum
  if currentPage == -1:
    currentPage = win.getCurrentTab()
  return getLanguageName(win, win.Tabs[currentPage].buffer)

proc getCurrentLanguageComment*(win: var MainWin,
          syntax: var tuple[line, blockStart, blockEnd: string], pageNum: int) =
  ## Gets the current line comment string and block comment string.
  ## If no comment can be found ``false`` is returned.
  
  var currentLang = getCurrentLanguage(win, pageNum)
  if currentLang != "":
    case currentLang.normalize()
    of "nimrod":
      syntax.blockStart = "discard \"\"\""
      syntax.blockEnd = "\"\"\""
      syntax.line = "#"
    else:
      var SourceLanguage = win.Tabs[pageNum].buffer.getLanguage()
      var bs = sourceLanguage.getMetadata("block-comment-start")
      var be = sourceLanguage.getMetadata("block-comment-end")
      var lc = sourceLanguage.getMetadata("line-comment-start")
      syntax.blockStart  = if bs != nil: $bs else: ""
      syntax.blockEnd    = if be != nil: $be else: ""
      syntax.line = if lc != nil: $lc else: ""
  else:
    syntax.blockStart = ""
    syntax.blockEnd = ""
    syntax.line = ""

proc setLanguage*(win: var MainWin, tab: int, lang: PSourceLanguage) =
  win.tabs[tab].buffer.setLanguage(lang)
  getCurrentLanguageComment(win, win.tempStuff.commentSyntax, tab) 

proc setHighlightSyntax*(win: var MainWin, tab: int, doHighlight: bool) =
  win.tabs[tab].buffer.setHighlightSyntax(doHighlight)
  win.tempStuff.commentSyntax = ("", "", "")

# -- Compilation-specific

proc GetCmd*(win: var MainWin, cmd, filename: string): string =
  ## ``cmd`` specifies the format string. ``findExe(exe)`` is allowed as well
  ## as ``#$``. The ``#$`` is replaced by ``filename``.
  var f = quoteIfContainsWhite(filename)
  proc promptNimrodPath(win: var MainWin): string =
    ## If ``settings.nimrodPath`` is not set, prompts the user for the nimrod path.
    ## Otherwise returns ``settings.nimrodPath``.
    if win.settings.nimrodPath == "":
      dialogs.info(win.w, "Unable to find nimrod executable. Please select it to continue.")
      win.settings.nimrodPath = ChooseFileToOpen(win.w, "")
    result = win.settings.nimrodPath
  
  if cmd =~ peg"\s* '$' y'findExe' '(' {[^)]+} ')' {.*}":
    var exe = quoteIfContainsWhite(findExe(matches[0]))
    if matches[0].normalize == "nimrod" and exe.len == 0:
      exe = quoteIfContainsWhite(promptNimrodPath(win))
    
    if exe.len == 0: exe = matches[0]
    result = exe & " " & matches[1] % f
  else:
    result = cmd % f
