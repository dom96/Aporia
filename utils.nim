#
#
#            Aporia - Nim IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Stdlib imports:
import gtk2, gtksourceview, glib2, pango, osproc, streams, asyncio, strutils, times
import tables, os, dialogs, pegs, osproc
from gdk2 import TRectangle, intersect, TColor, colorParse, TModifierType
# Local imports:
from CustomStatusBar import CustomStatusBar, StatusID

import AboutDialog

type
  AutoSettings* = object # Settings which should not be set by the user manually
    search*: SearchEnum # Search mode.
    wrapAround*: bool # Whether to wrap the search around.

    winMaximized*: bool # Whether the MainWindow is maximized on startup
    VPanedPos*: int32 # Position of the VPaned, which splits
                      # the sourceViewTabs and bottomPanelTabs
    winWidth*, winHeight*: int32 # The size of the window.

    recentlyOpenedFiles*: seq[string] # paths of recently opened files

    lastSelectedTab*: string # The tab filename that was selected when aporia was last closed.

    bottomPanelVisible*: bool # Whether the bottom panel is shown

  GlobalSettings* = object
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
    autoIndent*: bool # Whether to automatically indent
    toolBarVisible*: bool # Whether the top panel is shown
    suggestFeature*: bool # Whether the suggest feature is enabled
    compileUnsavedSave*: bool # Whether compiling unsaved files will make them appear saved in the front end.
    compileSaveAll*: bool # Whether compiling will save all opened unsaved files
    nimCmd*: string  # command template to use to exec the Nim compiler
    customCmd1*: string # command template to use to exec a custom command
    customCmd2*: string # command template to use to exec a custom command
    customCmd3*: string # command template to use to exec a custom command
    singleInstancePort*: int32 # Port used for listening socket to get filepaths
    showCloseOnAllTabs*: bool # Whether to show a close btn on all tabs.
    nimPath*: string # Path to the nim compiler
    wrapMode*: gtk2.TWrapMode # source view wrap mode.
    scrollPastBottom*: bool # Whether to scroll past bottom.
    singleInstance*: bool # Whether the program runs as single instance.
    restoreTabs*: bool    # Whether the program loads the tabs from the last session
    activateErrorTabOnErrors*: bool    # Whether the Error list tab will be shown when an error ocurs
    truncateLongTitles*: bool # Whether to truncate long titles to 20 characters
    keyCommentLines*:      ShortcutKey
    keyDeleteLine*:        ShortcutKey
    keyDuplicateLines*:    ShortcutKey
    keyQuit*:              ShortcutKey
    keyNewFile*:           ShortcutKey
    keyOpenFile*:          ShortcutKey
    keySaveFile*:          ShortcutKey
    keySaveFileAs*:        ShortcutKey
    keySaveAll*:           ShortcutKey
    keyUndo*:              ShortcutKey
    keyRedo*:              ShortcutKey
    keyCloseCurrentTab*:   ShortcutKey
    keyCloseAllTabs*:      ShortcutKey
    keyFind*:              ShortcutKey
    keyReplace*:           ShortcutKey
    keyFindNext*:          ShortcutKey
    keyFindPrevious*:      ShortcutKey
    keyGoToLine*:          ShortcutKey
    keyGoToDef*:           ShortcutKey
    keyToggleBottomPanel*: ShortcutKey
    keyCompileCurrent*:    ShortcutKey
    keyCompileRunCurrent*: ShortcutKey
    keyCompileProject*:    ShortcutKey
    keyCompileRunProject*: ShortcutKey
    keyStopProcess*:       ShortcutKey
    keyRunCustomCommand1*: ShortcutKey
    keyRunCustomCommand2*: ShortcutKey
    keyRunCustomCommand3*: ShortcutKey
    keyRunCheck*:          ShortcutKey

  ShortcutKey* = object
    keyval*: guint
    state*: guint

  MainWin* = object
    # Widgets
    w*: gtk2.PWindow
    suggest*: SuggestDialog
    nimLang*: PSourceLanguage
    scheme*: PSourceStyleScheme # color scheme the sourceview is meant to use
    sourceViewTabs*: PNotebook # Tabs which hold the sourceView
    statusBar*: CustomStatusBar

    infobar*: PInfoBar ## For encoding selection
    filecheckbar*: PInfoBar ## For accepting or rejecting file changes

    toolBar*: PToolBar # \
    # FIXME: should be notebook?
    bottomPanelTabs*: PNotebook
    outputTextView*: PTextView
    errorListWidget*: PTreeView

    findBar*: PHBox # findBar
    findEntry*: PEntry
    replaceEntry*: PEntry
    replaceLabel*: PLabel
    replaceBtn*: PButton
    replaceAllBtn*: PButton

    goLineBar*: GoLineBar

    FileMenu*: PMenu

    viewToolBarMenuItem*: PMenuItem # view menu
    viewBottomPanelMenuItem*: PMenuItem # view menu

    tabs*: seq[Tab] # Other

    tempStuff*: Temp # Just things to remember. TODO: Rename to `other' ?

    autoSettings*: AutoSettings
    globalSettings*: GlobalSettings
    oneInstSock*: AsyncSocket
    IODispatcher*: Dispatcher

  SuggestDialog* = object
    dialog*: gtk2.PWindow
    treeView*: PTreeView
    items*: seq[SuggestItem] ## Visible items (In the treeview)
    allItems*: seq[SuggestItem] ## All items found in current context.
    shown*: bool
    gotAll*: bool # Whether all suggest items have been read.
    currentFilter*: string
    tooltip*: gtk2.PWindow
    tooltipLabel*: PLabel

  ExecMode* = enum
    ExecNim, ExecRun, ExecCustom

  ExecOptions* = ref object
    command*: string
    workDir*: string
    mode*: ExecMode
    output*: bool
    onLine*: proc (win: var MainWin, opts: ExecOptions, line: string) {.closure.}
    onExit*: proc (win: var MainWin, opts: ExecOptions, exitcode: int) {.closure.}
    runAfterSuccess*: bool # If true, ``runAfter`` will only be ran on success.
    runAfter*: ExecOptions

  ExecThrTaskType* = enum
    ThrRun, ThrStop
  ExecThrTask* = object
    case typ*: ExecThrTaskType
    of ThrRun:
      command*: string
      workDir*: string
    of ThrStop: nil

  ExecThrEventType* = enum
    EvStarted, EvRecv, EvStopped
  ExecThrEvent* = object
    case typ*: ExecThrEventType
    of EvStarted:
      p*: Process
    of EvRecv:
      line*: string
    of EvStopped:
      exitCode*: int

  Temp = object
    lastSaveDir*: string # Last saved directory/last active directory
    stopSBUpdates*: bool

    currentExec*: ExecOptions # nil if nothing is being executed.
    compileSuccess*: bool
    execThread*: Thread[void]
    execProcess*: Process
    idleFuncId*: int32
    progressStatusID*: StatusID
    lastProgressPulse*: float
    errorMsgStarted*: bool
    compilationErrorBuffer*: string # holds error msg if it spans multiple lines.
    errorList*: seq[AporiaError]
    gotDefinition*: bool
    autoComplete*: AutoComplete

    recentFileMenuItems*: seq[PMenuItem] # Menu items to be destroyed.
    lastTab*: int # For reordering tabs, the last tab that was selected.
    commentSyntax*: tuple[line: string, blockStart: string, blockEnd: string]
    pendingFilename*: string # Filename which could not be opened due to encoding.
    plMenuItems*: tables.Table[string, tuple[mi: PCheckMenuItem, id: string]]
    stopPLToggle*: bool
    currentToggledLang*: string # ID of the currently active pl

  Tab* = ref object
    buffer*: PSourceBuffer
    sourceView*: PSourceView
    label*: PLabel
    closeBtn*: PButton # This is so that the close btn is only shown on selected tabs.
    filename*: string
    highlighted*: HighlightAll
    spbInfo*: tuple[lastUpper, value: float] # Scroll past bottom info
    lineEnding*: LineEnding
    lastEdit*: Time

  SuggestItem* = object
    nodeType*, name*, nimType*, file*, nmName*, docs*: string
    line*, col*: int32

  SearchEnum* = enum
    SearchCaseSens, SearchCaseInsens, SearchStyleInsens, SearchRegex, SearchPeg

  GoLineBar* = object
    bar*: PHBox
    entry*: PEntry

  ErrorType* = enum
    TETError, TETWarning

  AporiaError* = object
    kind*: ErrorType
    desc*, file*, line*, column*: string

  EncodingsAvailable* = enum
    UTF8 = "UTF-8", ISO88591 = "ISO-8859-1", GB2312 = "GB2312",
    Windows1251 = "Windows-1251", UTF16BE = "UTF-16BE", UTF16LE = "UTF-16LE"

  LineEnding* = enum
    leAuto = "Unknown", leLF = "LF", leCR = "CR", leCRLF = "CRLF"

  HighlightAll* = object
    isHighlighted*: bool
    text*: string # What is currently being highlighted in this tab
    forSearch*: bool # Whether highlightedText is done as a result of a search.
    idleID*: int32

  AutoComplete* = ref object
    thread*: Thread[void]
    sockThread*: Thread[void]
    taskRunning*, nimSuggestRunning*: bool
    onSugLine*: proc (line: string) {.closure.}
    onSugExit*: proc (exit: int) {.closure.}
    onSugError*: proc (error: string) {.closure.}

# -- Debug
proc echod*(s: varargs[string, `$`]) =
  when not defined(release) and system.appType != "gui":
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
      textView.scrollToMark(endMark, 0.0, false, 0.0, 1.0)

proc forceScrollToInsert*(win: var MainWin, tabIndex: int32 = -1) =
  ## Uses an idle proc to make sure that the SourceView scrolls. This is quite
  ## effective when the sourceview has just been initialised.
  var current = -1
  if tabIndex != -1: current = tabIndex
  else: current = win.sourceViewTabs.getCurrentPage()

  var mark = win.tabs[current].buffer.getInsert()
  win.tabs[current].sourceView.scrollToMark(mark, 0.25, false, 0.0, 0.0)

  # TODO: What if I remove the tab, while this is happening, segfault because
  # sourceview is gone? The likelihood of this happening is probably very unlikely
  # though.

  proc idleConfirmScroll(sv: PSourceView): gboolean {.cdecl.} =
    result = false

    var buff = sv.getBuffer()
    var insertMark = buff.getInsert()
    var insertIter: TTextIter
    buff.getIterAtMark(addr(insertIter), insertMark)
    var insertLoc: gdk2.TRectangle
    sv.getIterLocation(addr(insertIter), addr(insertLoc))

    var rect: gdk2.TRectangle
    sv.getVisibleRect(addr(rect))

    # Now check whether insert iter is inside the visible rect.
    # Width has to be higher than 0
    if insertLoc.width <= 0: insertLoc.width = 1
    let inside = intersect(addr(rect), addr(insertLoc), nil)
    if not inside:
      sv.scrollToMark(insertMark, 0.25, false, 0.0, 0.0)
      return true

  discard gIdleAdd(idleConfirmScroll, win.tabs[current].sourceview)

proc scrollToInsert*(win: var MainWin, tabIndex: int32 = -1) =
  var current = -1
  if tabIndex != -1: current = tabIndex
  else: current = win.sourceViewTabs.getCurrentPage()

  var mark = win.tabs[current].buffer.getInsert()
  win.tabs[current].sourceView.scrollToMark(mark, 0.25, false, 0.0, 0.0)

proc findTab*(win: var MainWin, filename: string, absolute: bool = true): int =
  for i in 0..win.tabs.len()-1:
    if absolute:
      if win.tabs[i].filename == filename:
        return i
    else:
      if win.tabs[i].filename.extractFilename == filename:
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
                      expand = false, foregroundColorColumn: gint = -1, visible = true) =
  ## Creates a new Text column.
  var c = treeViewColumnNew()
  var renderer = cellRendererTextNew()

  c.columnSetTitle(title)
  c.columnPackStart(renderer, expand)
  c.columnSetExpand(expand)
  c.columnSetResizable(true)
  c.columnSetVisible(visible)

  c.column_add_attribute(renderer, "text", column.gint)
  c.column_add_attribute(renderer, "foreground", foregroundColorColumn)

  doAssert tv.appendColumn(c) == column+1

# -- Useful ListStore functions
proc add*(ls: PListStore, val: string, col = 0) =
  var iter: TTreeIter
  ls.append(addr(iter))
  ls.set(addr(iter), col, val, -1)

# -- Useful Menu functions
proc createAccelMenuItem*(toolsMenu: PMenu, accGroup: PAccelGroup,
                         label: string, acc: guint,
                         action: proc (i: PMenuItem, p: pointer) {.cdecl.},
                         mask: TModifierType = accelerator_get_default_mod_mask(),
                         stockid: string = "") =
  var result: PMenuItem
  if stockid != "":
    result = imageMenuItemNewFromStock(stockid, nil)
  else:
    result = menu_item_new(label)

  if accelerator_valid(acc, mask):
    result.addAccelerator("activate", accGroup, acc, mask, ACCEL_VISIBLE)

  toolsMenu.append(result)
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

  proc idleConfirmPresent(y: PWindow): gboolean {.cdecl.} =
    y.present()
    result = not y.isActive()

  if not w.isActive():
    discard gIdleAdd(idleConfirmPresent, w)

# -- Others

proc getCurrentTab*(win: var MainWin): int =
  result = win.sourceViewTabs.getCurrentPage()
  if result < 0:
    result = 0

proc findProjectFile*(directory: string): tuple[projectFile, projectCfg: string] =
  ## Finds the .nim project file in ``directory``.
  # Find project file
  var configFiles: seq[string] = @[]
  for cfgFile in walkFiles(directory / "*.nim.cfg"):
    configFiles.add(cfgFile)
  let projectCfgFile = if configFiles.len != 1: "" else: configFiles[0]
  var projectFile = projectCfgFile[0 .. ^8]
  if not existsFile(projectFile):
    projectFile = ""
  return (projectFile, projectCfgFile)

proc isTemporary*(t: Tab): bool =
  ## Determines whether ``t`` is saved in /tmp
  return t.filename.startsWith(getTempDir())

proc saved*(t: Tab): bool =
  ## Determines Tab's saved state,
  assert(not t.buffer.isNil)
  return not t.buffer.getModified()

proc `saved=`*(t: Tab, b: bool) =
  assert(not t.buffer.isNil)
  t.buffer.setModified(not b)

proc detectLineEndings*(text: string): LineEnding =
  var i = 0
  while true:
    case text[i]
    of '\L':
      return leLF
    of '\c':
      if text[i + 1] == '\L': return leCRLF
      else: return leCR
    else:
      if text[i] == '\0': return leAuto
    i.inc

proc srepr(le: LineEnding, auto: string): string =
  case le
  of leLF: "\L"
  of leCR: "\C"
  of leCRLF: "\c\L"
  of leAuto: auto

proc normalize*(le: LineEnding, text: string): string =
  ## Normalizes newlines and strips trailing whitespace.
  result = ""
  var i = 0
  while true:
    case text[i]
    of ' ', '\t':
      # peek and see if a newline follows:
      var j = i+1
      while text[j] in {' ', '\t'}: inc j
      if text[j] in {'\L', '\C'}: i = j-1
      else: result.add text[i]
    of '\L':
      result.add(le.srepr("\L"))
    of '\C':
      if text[i + 1] == '\L':
        result.add(le.srepr("\c\L"))
        i.inc
      else:
        result.add(le.srepr("\c"))
    of '\0': return
    else:
      result.add text[i]

    i.inc

proc addExtraNL*(le: LineEnding, text: var string) =
  const defaultLE = "\L"
  let sle = srepr(le, defaultLE)
  if not text.endswith(sle):
    text.add(sle)

# -- Programming Language handling
proc getCurrentLanguage*(win: var MainWin, pageNum: int = -1): string =
  ## Returns the current language ID.
  ##
  ## ``""`` is returned if there is no syntax highlighting for the current doc.
  var currentPage = pageNum
  if currentPage == -1:
    currentPage = win.getCurrentTab()
  var isHighlighted = win.tabs[currentPage].buffer.getHighlightSyntax()
  if isHighlighted:
    var sourceLanguage = win.tabs[currentPage].buffer.getLanguage()
    if sourceLanguage == nil: return ""
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
    var sourceLanguage = buffer.getLanguage()
    if sourceLanguage == nil: return "Plain Text"
    return $sourceLanguage.getName()
  else:
    return "Plain Text"

proc getLanguageName*(win: var MainWin, pageNum: int = -1): string =
  ## Returns the language name of the ``pageNum`` tab.
  var currentPage = pageNum
  if currentPage == -1:
    currentPage = win.getCurrentTab()
  return getLanguageName(win, win.tabs[currentPage].buffer)

proc getCurrentLanguageComment*(win: var MainWin,
          syntax: var tuple[line, blockStart, blockEnd: string], pageNum: int) =
  ## Gets the current line comment string and block comment string.
  ## If no comment can be found ``false`` is returned.

  var currentLang = getCurrentLanguage(win, pageNum)
  if currentLang != "":
    case currentLang.normalize()
    of "nim":
      syntax.blockStart = "discard \"\"\""
      syntax.blockEnd = "\"\"\""
      syntax.line = "#"
    else:
      var sourceLanguage = win.tabs[pageNum].buffer.getLanguage()
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

proc getCmd*(win: var MainWin, cmd, filename: string): string =
  ## ``cmd`` specifies the format string. ``findExe(exe)`` is allowed as well
  ## as ``#$``. The ``#$`` is replaced by ``filename``.
  var f = quoteIfContainsWhite(filename)
  proc promptNimPath(win: var MainWin): string =
    ## If ``settings.nimPath`` is not set, prompts the user for the nim path.
    ## Otherwise returns ``settings.nimPath``.
    if not fileExists(win.globalSettings.nimPath):
      dialogs.info(win.w, "Unable to find nim executable. Please select it to continue.")
      win.globalSettings.nimPath = chooseFileToOpen(win.w, "")
    result = win.globalSettings.nimPath

  if cmd =~ peg"\s* '$' y'findExe' '(' {[^)]+} ')' {.*}":
    var exe = quoteIfContainsWhite(findExe(matches[0]))
    if matches[0].normalize == "nim" and exe.len == 0:
      exe = quoteIfContainsWhite(promptNimPath(win))

    if exe.len == 0: exe = matches[0]
    result = exe & " " & matches[1] % f
  else:
    result = cmd % f

when isMainModule:
  assert detectLineEndings("asfasfa\c\Lasfasf") == leCRLF
  assert detectLineEndings("asfasfa\casas") == leCR
  assert detectLineEndings("asfasfa\Lasas") == leLF
