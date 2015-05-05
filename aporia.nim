#
#
#            Aporia - Nim IDE
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Stdlib imports:
import glib2, gtk2, gtksourceview, dialogs, os, pango, osproc, strutils
import gdk2 except `delete` # Don't import delete to avoid "ambiguous identifier" error under Windows
import pegs, streams, times, parseopt, parseutils, asyncio, sockets, encodings
import tables, algorithm
# Local imports:
import settings, utils, cfg, search, suggest, AboutDialog, processes,
       CustomStatusBar, AutoComplete
{.push callConv:cdecl.}

const
  GTKVerReq = (2'i32, 24'i32, 0'i32) # Version of GTK required for Aporia to run.
  aporiaVersion = "0.1.3"
  helpText = """./aporia [args] filename...
  -v  --version  Reports aporia's version
  -h  --help Shows this message
"""

var win: utils.MainWin
win.tabs = @[]

var lastSession: seq[string] = @[]

proc writeHelp() =
  echo(helpText)
  quit(QuitSuccess)

proc writeVersion() =
  echo("Aporia v$1 compiled at $2 $3.\nCopyright (c) Dominik Picheta 2010-2015" %
       [aporiaVersion, CompileDate, CompileTime])
  quit(QuitSuccess)

proc parseArgs(): seq[string] =
  result = @[]
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      result.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": writeHelp()
      of "version", "v": writeVersion()
    of cmdEnd: assert(false) # cannot happen

var loadFiles = parseArgs()

# Load the settings
var cfgErrors: seq[TError] = @[]
let (auto, global) = cfg.load(cfgErrors, lastSession)
win.autoSettings = auto
win.globalSettings = global

proc showConfigErrors*() =
  if cfgErrors.len > 0:
    for error in cfgErrors:
      addError(win, error)
    dialogs.warning(win.w, "Error parsing config file, see Error List.")

proc updateMainTitle(pageNum: int) =
  if win.tabs.len()-1 >= pageNum:
    var title = ""
    if win.tabs[pageNum].filename == "":
      title = "Untitled"
    else:
      title = win.tabs[pageNum].filename.extractFilename
    if not win.tabs[pageNum].saved:
      title.add("*")
    title.add(" - Aporia")
    win.w.setTitle(title)

proc plCheckUpdate(pageNum: int) =
  ## Updates the 'check state' of the syntax highlighting CheckMenuItems,
  ## depending on the syntax highlighting language that has been set.
  let currentToggledLang = win.tempStuff.currentToggledLang
  let newLang = win.getCurrentLanguage(pageNum)
  assert win.tempStuff.plMenuItems.hasKey(currentToggledLang)
  assert win.tempStuff.plMenuItems.hasKey(newLang)
  win.tempStuff.stopPLToggle = true
  win.tempStuff.plMenuItems[currentToggledLang].mi.itemSetActive(false)
  win.tempStuff.plMenuItems[newLang].mi.itemSetActive(true)
  win.tempStuff.currentToggledLang = newLang
  win.tempStuff.stopPLToggle = false

proc setTabTooltip(t: Tab) =
  ## (Re)sets the tab tooltip text.
  if t.filename != "":
    var tooltip = "<b>Path: </b> " & t.filename & "\n" &
                  "<b>Language: </b> " & getLanguageName(win, t.buffer) & "\n" &
                  "<b>Line Ending: </b> " & $t.lineEnding
    if t.filename.startsWith(getTempDir()):
      tooltip.add("\n<i>File is saved in temporary files and may be deleted.</i>")
    t.label.setTooltipMarkup(tooltip)
  else:
    var tooltip = "<i>Tab is not saved.</i>\n" &
                  "<b>Language: </b> " & getLanguageName(win, t.buffer) & "\n" &
                  "<b>Line Ending: </b> " & $t.lineEnding
    t.label.setTooltipMarkup(tooltip)

proc updateTabUI(t: Tab) =
  ## Updates Tab's label and tooltip. Call this when the tab's filename or
  ## language changes.
  var name = ""
  if t.filename == "":
    name = "Untitled"
  else:
    name = extractFilename(t.filename)
  if not t.saved:
    name.add(" *")

  if t.saved and t.isTemporary:
    t.label.setMarkup(name & "<span color=\"#CC0E0E\"> *</span>")
  else:
    t.label.setText(name)
  setTabTooltip(t)

proc saveTab(tabNr: int, startpath: string, updateGUI: bool = true) =
  ## If tab's filename is ``""`` and the user clicks "Cancel", the filename will
  ## remain ``""``.

  # TODO: Refactor this function. It's a disgrace.
  if tabNr < 0: return
  if win.tabs[tabNr].saved: return
  var path = ""
  if win.tabs[tabNr].filename == "":
    path = chooseFileToSave(win.w, startpath)
    if path != "":
      # Change syntax highlighting for this tab.
      var langMan = languageManagerGetDefault()
      var lang = langMan.guessLanguage(path, nil)
      if lang != nil:
        win.setLanguage(tabNr, lang)
        win.setHighlightSyntax(tabNr, true)
      else:
        win.setHighlightSyntax(tabNr, false)
      if tabNr == win.getCurrentTab:
        plCheckUpdate(tabNr)
  else:
    path = win.tabs[tabNr].filename

  if path != "":
    var buffer = PTextBuffer(win.tabs[tabNr].buffer)
    # Get the text from the TextView
    var startIter: TTextIter
    buffer.getStartIter(addr(startIter))

    var endIter: TTextIter
    buffer.getEndIter(addr(endIter))

    var text = $buffer.getText(addr(startIter), addr(endIter), false)

    var config = false
    if path == os.getConfigDir() / "Aporia" / "config.global.ini":
      # If we are overwriting Aporia's config file. Validate it.
      cfgErrors = @[]
      var newSettings = cfg.loadGlobal(cfgErrors, newStringStream($text))
      if cfgErrors.len > 0:
        showConfigErrors()
        return
      win.globalSettings = newSettings
      config = true

    # Handle text before saving
    text = win.tabs[tabNr].lineEnding.normalize(text, win.globalSettings.keepEmptyLines)
    win.tabs[tabNr].lineEnding.addExtraNL(text)

    # Save it to a file
    var f: TFile
    if open(f, path, fmWrite):
      f.write(text)
      f.close()

      win.tempStuff.lastSaveDir = splitFile(path).dir

      # Change the tab name and .Tabs.filename etc.
      win.tabs[tabNr].filename = path

      if updateGUI:
        win.tabs[tabNr].saved = true

        updateMainTitle(tabNr)
        if config:
          win.statusbar.setTemp("Config saved successfully.", UrgSuccess)
        else:
          win.statusbar.setTemp("File saved successfully.", UrgSuccess)
    else:
      error(win.w, "Unable to write to file: " & oSErrorMsg(osLastError()))

proc saveTabAs(tab: int, startPath: string): bool =
  ## Returns whether we saved to a different filename.
  var (filename, saved) = (win.tabs[tab].filename, win.tabs[tab].saved)

  win.tabs[tab].saved = false
  win.tabs[tab].filename = ""
  # saveTab will ask the user for a filename if the tab's filename is "".
  saveTab(tab, startpath)
  # If the user cancels the save file dialog. Restore the previous filename
  # and saved state
  if win.tabs[tab].filename == "":
    win.tabs[tab].filename = filename
    win.tabs[tab].saved = saved

  result = win.tabs[tab].filename != filename

  updateMainTitle(tab)

proc saveAllTabs() =
  for i in 0..high(win.tabs):
    saveTab(i, os.splitFile(win.tabs[i].filename).dir)

proc exit() =
  # gather some settings
  win.autoSettings.VPanedPos = PPaned(win.sourceViewTabs.getParent()).getPosition()
  win.autoSettings.winWidth = win.w.allocation.width
  win.autoSettings.winHeight = win.w.allocation.height

  # save the settings
  win.save()
  # then quit
  main_quit()

# GTK Events
# -- w(PWindow)

proc confirmUnsaved(win: var MainWin, t: Tab): int =
  var askSave = win.w.messageDialogNew(0, MessageWarning, BUTTONS_NONE, nil)

  askSave.setTransientFor(win.w)
  if t.filename != "":
    let name = t.filename.extractFilename
    if t.isTemporary:
      if t.saved:
        askSave.setMarkup(name & " is saved in your system's temporary" &
                          " directory, what would you like to do?")
        askSave.addButtons("_Save in a different directory", ResponseAccept,
                           STOCK_CANCEL, ResponseCancel,
                           "Close _without saving", ResponseReject, nil)
      else:
        askSave.setMarkup("An old version of " & name & " is saved in your " &
                          "system's temporary directory. What would you like to do?")
        askSave.addButtons("Save in a _different directory", ResponseAccept,
                           STOCK_SAVE, ResponseOK,
                           STOCK_CANCEL, ResponseCancel,
                           "Close _without saving", ResponseReject, nil)
    else:
      askSave.setMarkup(name & " is not saved, would you like to save it?")
      askSave.addButtons(STOCK_SAVE, ResponseAccept, STOCK_CANCEL, ResponseCancel,
          "Close _without saving", ResponseReject, nil)
  else:
    askSave.setMarkup("Would you like to save this tab?")
    askSave.addButtons(STOCK_SAVE, ResponseAccept, STOCK_CANCEL, ResponseCancel,
              "Close _without saving", ResponseReject, nil)

  # TODO: GtkMessageDialog's label seems to wrap lines...

  result = askSave.run()
  gtk2.destroy(PWidget(askSave))

proc askCloseTab(tab: int): bool =
  result = true
  if not win.tabs[tab].saved and not win.tabs[tab].isTemporary:
    # Only ask to save if file isn't empty or has a "history" (undo can be performed)
    if win.tabs[tab].buffer.get_char_count != 0 or can_undo(win.tabs[tab].buffer):
      var resp = win.confirmUnsaved(win.tabs[tab])
      if resp == RESPONSE_ACCEPT:
        saveTab(tab, os.splitFile(win.tabs[tab].filename).dir)
        result = true
      elif resp == RESPONSE_CANCEL:
        result = false
      elif resp == RESPONSE_REJECT:
        result = true
      else:
        result = false

  if win.tabs[tab].isTemporary:
    var resp = win.confirmUnsaved(win.tabs[tab])
    if resp == RESPONSE_ACCEPT:
      result = saveTabAs(tab, os.splitFile(win.tabs[tab].filename).dir)
    elif resp == RESPONSE_OK:
      assert(not win.tabs[tab].saved)
      saveTab(tab, os.splitFile(win.tabs[tab].filename).dir)
      result = true
    elif resp == RESPONSE_CANCEL:
      result = false
    elif resp == RESPONSE_REJECT:
      result = true
    else:
      result = false

proc delete_event(widget: PWidget, event: PEvent, user_data: Pgpointer): gboolean =
  var quit = true
  for i in win.tabs.low .. win.tabs.len-1:
    if not win.tabs[i].saved or win.tabs[i].isTemporary:
      win.sourceViewTabs.setCurrentPage(i.int32)
      quit = askCloseTab(i)
      if not quit: break
  # If false is returned the window will close
  return not quit

proc windowState_Changed(widget: PWidget, event: PEventWindowState,
                         user_data: Pgpointer) =
  win.autoSettings.winMaximized = (event.newWindowState and
                               WINDOW_STATE_MAXIMIZED) != 0

  if (event.newWindowState and WINDOW_STATE_ICONIFIED) != 0:
    win.suggest.hide()

proc window_configureEvent(widget: PWidget, event: PEventConfigure,
                           ud: Pgpointer): gboolean =
  if win.suggest.shown:
    var current = win.sourceViewTabs.getCurrentPage()
    var tab     = win.tabs[current]
    var start: TTextIter
    # Get the iter at the cursor position.
    tab.buffer.getIterAtMark(addr(start), tab.buffer.getInsert())
    moveSuggest(win, addr(start), tab)

  return false

proc cycleTab(win: var MainWin) =
  var current = win.sourceViewTabs.getCurrentPage()
  if current + 1 >= win.tabs.len():
    current = 0
  else:
    current.inc(1)

  # select next tab
  win.sourceViewTabs.setCurrentPage(current)

proc closeTab(tab: int) =
  proc recentlyOpenedAdd(filename: string) =
    for i in 0 .. win.autoSettings.recentlyOpenedFiles.len-1:
      if win.autoSettings.recentlyOpenedFiles[i] == filename:
        system.delete(win.autoSettings.recentlyOpenedFiles, i)
        break
    win.autoSettings.recentlyOpenedFiles.add(filename)

  var close = askCloseTab(tab)

  if close:
    # Add to recently opened files.
    if win.tabs[tab].filename != "":
      recentlyOpenedAdd(win.tabs[tab].filename)
    system.delete(win.tabs, tab)
    win.sourceViewTabs.removePage(int32(tab))

proc window_keyPress(widg: PWidget, event: PEventKey,
                          userData: Pgpointer): gboolean =
  result = false
  var modifiers = acceleratorGetDefaultModMask()
  
  if (event.state and modifiers) == CONTROL_MASK:
    # Ctrl pressed.
    case event.keyval
    of KeyTab:
      # Ctrl + Tab
      win.cycleTab()
      return true
    of KeyW:
      # Ctrl + W
      closeTab(win.sourceViewTabs.getCurrentPage())
      return true
    else:
      discard

  if event.keyval == KeyEscape:
    # Esc pressed
    win.findBar.hide()
    win.goLineBar.bar.hide()
    var current = win.sourceViewTabs.getCurrentPage()
    win.tabs[current].sourceView.grabFocus()


# -- SourceView(PSourceView) & SourceBuffer

proc updateHighlightAll(buffer: PTextBuffer, markName: string = "") =
  # Called when the highlighted text should be updated. i.e. new selection
  # has been made.
  var insert, selectBound: TTextIter
  if buffer.getSelectionBounds(addr(insert), addr(selectBound)):
    # There is a selection
    let frmLn = getLine(addr(insert)) + 1
    let toLn = getLine(addr(selectBound)) + 1
    # Highlighting
    if frmLn == toLn and win.globalSettings.selectHighlightAll:
      template h: expr = win.tabs[getCurrentTab(win)].highlighted
      # Same line.
      var term = buffer.getText(addr(insert), addr(selectBound), false)
      highlightAll(win, $term, false)
      if not win.globalSettings.searchHighlightAll and h.forSearch and
         markName == "selection_bound":
        # Override the search selection block, this means that after searching
        # selecting text manually will still highlight things instead of you
        # having to close the find bar.
        h = newNoHighlightAll()
    else: # multiple lines selected
      if win.globalSettings.selectHighlightAll:
        stopHighlightAll(win, false)
  else:
    if win.globalSettings.selectHighlightAll:
      stopHighlightAll(win, false)

proc updateStatusBar(buffer: PTextBuffer, markName: string = "") =
  # Incase this event gets fired before
  # statusBar is initialized
  if win.statusbar != nil and not win.tempStuff.stopSBUpdates:
    var insert, selectBound: TTextIter
    if buffer.getSelectionBounds(addr(insert), addr(selectBound)):
      # There is a selection
      let frmLn = getLine(addr(insert)) + 1
      let toLn = getLine(addr(selectBound)) + 1
      let frmChar = getLineOffset(addr(insert))
      let toChar = getLineOffset(addr(selectBound))
      win.statusbar.setDocInfoSelected(frmLn, toLn, frmChar, toChar)
    else:
      let ln = getLine(addr(insert)) + 1
      let ch = getLineOffset(addr(insert))
      win.statusbar.setDocInfo(ln, ch)

proc cursorMoved(buffer: PTextBuffer, location: PTextIter,
                 mark: PTextMark, user_data: Pgpointer){.cdecl.} =
  var markName = mark.getName()
  if markName == nil:
    return # We don't want anonymous marks.
  if $markName == "insert" or $markName == "selection_bound":
    updateStatusBar(buffer, $markName)
    updateHighlightAll(buffer, $markName)

proc onCloseTab(btn: PButton, child: PWidget)
proc tab_buttonRelease(widg: PWidget, ev: PEventButton,
                       userDat: PWidget): gboolean
proc createTabLabel(name: string, t_child: PWidget, filename: string): tuple[box: PWidget,
                    label: PLabel, closeBtn: PButton] =
  var eventBox = eventBoxNew()
  eventBox.setVisibleWindow(false)
  discard signal_connect(eventBox, "button-release-event",
                    SIGNAL_FUNC(tab_buttonRelease), t_child)

  var box = hboxNew(false, 0)
  var label = labelNew(name)
  if filename.startsWith(getTempDir()):
    # If this is a temporary tab, mark it as such.
    label.setMarkup(name & "<span color=\"#CC0E0E\"> *</span>")

  var closebtn = buttonNew()
  closeBtn.setLabel(nil)
  var iconSize = iconSizeFromName("tabIconSize")
  if iconSize == 0:
   iconSize = iconSizeRegister("tabIconSize", 10, 10)
  var image = imageNewFromStock(STOCK_CLOSE, iconSize)
  discard gSignalConnect(closebtn, "clicked", G_Callback(onCloseTab), t_child)
  closebtn.setImage(image)
  gtk2.setRelief(closebtn, RELIEF_NONE)
  box.packStart(label, true, true, 0)
  box.packEnd(closebtn, false, false, 0)
  box.showAll()

  eventBox.add(box)
  return (eventBox, label, closeBtn)

proc onModifiedChanged(buffer: PTextBuffer, theTab: gpointer) =
  ## This signal is called when the modification state of ``buffer`` is changed.
  # <del>*Warning* we assume here that the currently selected tab was modified.</del>
  var ctab = cast[Tab](theTab)
  #assert ((current > 0) and (current < win.tabs.len))
  updateTabUI(cTab)
  updateMainTitle(win.sourceViewTabs.getCurrentPage())

proc onChanged(buffer: PTextBuffer, sv: PSourceView) =
  ## This function is connected to the "changed" event on `buffer`.
  updateStatusBar(buffer, "")
  updateHighlightAll(buffer)

proc sourceViewKeyPress(sourceView: PWidget, event: PEventKey,
                          userData: Pgpointer): gboolean =
  result = false
  let ctrlPressed = (event.state and ControlMask) != 0
  let keyNameCString = keyval_name(event.keyval)
  if keyNameCString == nil: return
  let key = $keyNameCString
  case key.toLower()
  of "up", "down", "page_up", "page_down":
    if win.globalSettings.suggestFeature and win.suggest.shown:
      var selection = win.suggest.treeview.getSelection()
      var selectedIter: TTreeIter
      var TreeModel = win.suggest.treeView.getModel()

      let childrenLen = TreeModel.iter_n_children(nil)

      # Get current tab(For tooltip)
      var current = win.sourceViewTabs.getCurrentPage()
      var tab     = win.tabs[current]

      template nextTimes(t: expr): stmt {.immediate.} =
        for i in 0..t:
          if selectedPath.getIndices[]+1 < childrenLen:
            next(selectedPath)
      template prevTimes(t: expr): stmt {.immediate.} =
        for i in 0..t:
          discard prev(selectedPath)

      if selection.getSelected(cast[PPGtkTreeModel](addr(TreeModel)),
                               addr(selectedIter)):
        var selectedPath = TreeModel.getPath(addr(selectedIter))

        var moved = false
        case key.toLower():
        of "up":
          moved = prev(selectedPath)
        of "down":
          moved = true
          next(selectedPath)
        of "page_up":
          moved = true
          prevTimes(5)
        of "page_down":
          moved = true
          nextTimes(5)

        if moved:
          # selectedPath is now the next or prev path.
          selection.selectPath(selectedPath)
          win.suggest.treeview.scroll_to_cell(selectedPath, nil, false, 0.5, 0.5)
          var index = selectedPath.getIndices()[]
          if win.suggest.items.len() > index:
            win.showTooltip(tab, win.suggest.items[index], selectedPath)
      else:
        # No item selected, select the first one.
        var selectedPath = tree_path_new_first()
        selection.selectPath(selectedPath)
        win.suggest.treeview.scroll_to_cell(selectedPath, nil, false, 0.5, 0.5)
        var index = selectedPath.getIndices()[]
        assert(index == 0)
        if win.suggest.items.len() > index:
          win.showTooltip(tab, win.suggest.items[index], selectedPath)

      # Return true to stop this event from moving the cursor down in the
      # source view.
      return true

  of "left", "right", "home", "end", "delete":
    if win.globalSettings.suggestFeature and win.suggest.shown:
      win.suggest.hide()

  of "return", "space", "tab", "period":
    if win.globalSettings.suggestFeature and win.suggest.shown:
      echod("[Suggest] Selected.")
      var selection = win.suggest.treeview.getSelection()
      var selectedIter: TTreeIter
      var TreeModel = win.suggest.treeView.getModel()
      if selection.getSelected(cast[PPGtkTreeModel](addr(TreeModel)),
                               addr(selectedIter)):
        var selectedPath = TreeModel.getPath(addr(selectedIter))
        var index = selectedPath.getIndices()[]
        win.insertSuggestItem(index)

        return key.toLower() != "period"

  of "backspace":
    let tab = win.tabs[getCurrentPage(win.sourceViewTabs)]
    
    var endIter: TTextIter
    tab.buffer.getIterAtMark(addr endIter, getInsert(tab.buffer))
    let endOffset = getOffset(addr endIter)

    var selectIter: TTextIter
    tab.buffer.getIterAtMark(addr selectIter, getSelectionBound(tab.buffer))
    let selectOffset = getOffset(addr selectIter)
    
    if win.globalSettings.deleteByIndent and endOffset == selectOffset:
      # Get an iter behind by tab length.
      var startIter: TTextIter = endIter
      var skipForward = false
      var lenToDel = 0
      for i in 0 .. <win.globalSettings.indentWidth:
        if backwardChar(addr startIter): # Can move back.
          if getChar(addr startIter).char != ' ':
            discard forwardChar(addr startIter) # move forward again
            break
          else:
            lenToDel += 1
        else:
          skipForward = true
          break
      if lenToDel > 1:
        if not skipForward:
          discard forwardChar(addr startIter) # move forward because 'backspace' deletes 1 too
        tab.buffer.delete(addr startIter, addr endIter)
    
    if win.globalSettings.suggestFeature and win.suggest.shown:
      # Get an iter one char behind.
      var startIter: TTextIter = endIter
      if (addr(startIter)).backwardChar(): # Can move back.
        # Get the character immediately behind.
        var behind = (addr(startIter)).getText(addr(endIter))
        assert(behind.len() == 1)
        if $behind == ".": # Note the $, I guess I must convert it into a nimstr
          win.suggest.hide()
        else:
          # handled in ...KeyRelease
          discard
  else:
    discard

proc sourceViewKeyRelease(sourceView: PWidget, event: PEventKey,
                          userData: Pgpointer): gboolean =
  result = true
  let ctrlPressed = (event.state and ControlMask) != 0
  let keyNameCString = keyval_name(event.keyval)
  if keyNameCString == nil: return
  let key = $keyNameCString
  case key.toLower()
  of "period":
    discard
    # TODO: Disable implicit invocation of suggest until it's more stable.
    #if win.globalSettings.suggestFeature and win.getCurrentLanguage() == "nim":
    #  if win.suggest.items.len() != 0: win.suggest.clear()
    #  doSuggest(win)

  of "backspace":
    if win.globalSettings.suggestFeature and win.suggest.shown:
      # Don't need to know the char behind, because if it is a dot, then
      # the suggest dialog is hidden by ...KeyPress

      win.filterSuggest()
      win.doMoveSuggest()
  of "space":
    if win.globalSettings.suggestFeature and not win.suggest.shown and
        key.toLower() == "space" and ctrlPressed and
        win.getCurrentLanguage() == "nim":
      if win.suggest.items.len() != 0: win.suggest.clear()
      doSuggest(win)
      result = false
      #win.filterSuggest()
  else:
    if key.toLower() notin ["up", "down", "page_up", "page_down", "home", "end"]:

      if win.globalSettings.suggestFeature and win.suggest.shown:
        win.filterSuggest()
        win.doMoveSuggest()

proc sourceViewMousePress(sourceView: PWidget, ev: PEvent, usr: gpointer): gboolean =
  win.suggest.hide()

proc addTab(name, filename: string, setCurrent: bool = true, encoding = "utf-8"): int
proc goToDef_Activate(i: PMenuItem, p: pointer) {.cdecl.} =
  let currentPage = win.sourceViewTabs.getCurrentPage()
  let tab = win.tabs[currentPage]
  if win.getCurrentLanguage(currentPage) != "nim":
    win.statusbar.setTemp("This feature is only supported for Nim.", UrgError)
    return

  var cursor: TTextIter
  tab.buffer.getIterAtMark(addr(cursor), tab.buffer.getInsert())

  proc onSugLine(win: var MainWin, line: string) {.closure.} =
    if win.tempStuff.gotDefinition:
      return
    var def: TSuggestItem
    if parseIDEToolsLine("def", line, def):
      win.tempStuff.gotDefinition = true
      let existingTab = win.findTab(def.file, true)
      if existingTab != -1:
        win.sourceViewTabs.setCurrentPage(existingTab.gint)
      else:
        doAssert addTab("", def.file, true) != -1

      let currentPage = win.sourceViewTabs.getCurrentPage()
      # Go to that line/col
      var iter: TTextIter
      win.tabs[currentPage].buffer.getIterAtLineIndex(addr(iter),
          def.line-1, def.col-1)

      win.tabs[currentPage].buffer.placeCursor(addr(iter))

      win.forceScrollToInsert()

      echod(def.repr())

  proc onSugExit(win: var MainWin, exitCode: int) {.closure.} =
    if not win.tempStuff.gotDefinition:
      win.statusbar.setTemp("Definition retrieval failed.", UrgError, 5000)

  proc onSugError(win: var MainWin, error: string) {.closure.} =
    if not win.tempStuff.gotDefinition:
      win.statusbar.setTemp("Definition retrieval failed: " & error,
          UrgError, 5000)

  var err = win.asyncGetDef(tab.filename, getLine(addr cursor),
                  getLineOffset(addr cursor), onSugLine, onSugExit, onSugError)
  if err != "":
    win.statusbar.setTemp(err, UrgError, 5000)

proc sourceView_PopulatePopup(entry: PTextView, menu: PMenu, u: pointer) =
  if win.getCurrentLanguage() == "nim":
    createSeparator(menu)
    createMenuItem(menu, "Go to definition...", goToDef_Activate)

proc sourceView_Adjustment_valueChanged(adjustment: PAdjustment,
    spb: ptr tuple[lastUpper, value: float]) =
  let value = adjustment.getValue
  if adjustment.getUpper == spb[][0]:
    spb[][1] = value

proc sourceView_sizeAllocate(sourceView: PSourceView,
    allocation: gdk2.PRectangle, spb: ptr tuple[lastUpper, value: float]) =
  # TODO: This implementation has some issues: when we add a new line
  # when at the very bottom of the TextView, the TextView jumps up and down.
  # TODO: Go back to my old implementation. Where the adjustment's upper
  # value only gets adjusted when scrolling past bottom. This will get rid of
  # the scroll bar jumping.

  let adjustment = sourceView.get_vadjustment()
  var upper = adjustment.get_upper()
  let pagesize = adjustment.get_page_size()
  # we have less lines than the viewport can hold
  if upper == pagesize:
    let buffer = sourceView.getBuffer()
    var iter: TTextIter
    getIterAtLine(buffer, addr iter, buffer.getLineCount)
    var y, height: gint
    sourceView.getLineYRange(addr iter, addr y, addr height)
    upper = gdouble(y + height)
    #echo("Changed upper to ", upper)
  let lineheight = 14.0
  let set_to = upper + pagesize - lineheight
  adjustment.set_upper(set_to)
  #echo("New upper: ", setTo)
  # scroll back to our old position, unless we actually scroll downward,
  # which means we just added a new line
  if adjustment.get_value() < spb[][1]:
    adjustment.set_value(spb[][1])
    #echo("New Value: ", spb[][1])
  spb[] = (set_to, adjustment.get_value())

# Other(Helper) functions

proc initSourceView(sourceView: var PSourceView, scrollWindow: var PScrolledWindow,
                    buffer: var PSourceBuffer) =
  # This gets called by addTab
  # Each tabs creates a new SourceView
  # SourceScrolledWindow(ScrolledWindow)
  scrollWindow = scrolledWindowNew(nil, nil)
  scrollWindow.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  scrollWindow.show()

  # SourceView(gtkSourceView)
  sourceView = sourceViewNew(buffer)
  sourceView.setInsertSpacesInsteadOfTabs(true)
  sourceView.setIndentWidth(win.globalSettings.indentWidth)
  sourceView.setShowLineNumbers(win.globalSettings.showLineNumbers)
  sourceView.setHighlightCurrentLine(
               win.globalSettings.highlightCurrentLine)
  sourceView.setShowRightMargin(win.globalSettings.rightMargin)
  sourceView.setAutoIndent(win.globalSettings.autoIndent)
  sourceView.setSmartHomeEnd(SmartHomeEndBefore)
  sourceView.setWrapMode(win.globalSettings.wrapMode)
  discard signalConnect(sourceView, "button-press-event",
                        SIGNALFUNC(sourceViewMousePress), nil)
  discard gSignalConnect(sourceView, "populate-popup",
                         GCallback(sourceViewPopulatePopup), nil)

  var font = font_description_from_string(win.globalSettings.font)
  sourceView.modifyFont(font)

  scrollWindow.add(sourceView)
  sourceView.show()

  buffer.setHighlightMatchingBrackets(
      win.globalSettings.highlightMatchingBrackets)

  discard signalConnect(sourceView, "key-press-event",
                        SIGNALFUNC(sourceViewKeyPress), nil)
  discard signalConnect(sourceView, "key-release-event",
                        SIGNALFUNC(sourceViewKeyRelease), nil)

  # -- Set the syntax highlighter scheme
  buffer.setScheme(win.scheme)

proc addTab(name, filename: string, setCurrent: bool = true,
            encoding = "utf-8"): int =
  ## Adds a tab. If filename is not "", a file is read and set as the content
  ## of the new tab. If name is "" it will be either "Unknown" or the last part
  ## of the filename.
  ## If filename doesn't exist EIO is raised.
  ##
  ## Returns the index of the added tab (or existing tab if setCurrent is true).
  ## ``-1`` is returned upon error.
  assert(win.nimLang != nil)

  var buffer: PSourceBuffer = sourceBufferNew(win.nimLang)

  if filename != nil and filename != "":
    if setCurrent:
      # If a tab with the same filename already exists select it.
      var existingTab = win.findTab(filename)
      if existingTab != -1:
        # Select the existing tab
        win.sourceViewTabs.setCurrentPage(int32(existingTab))
        return existingTab

    # Guess the language of the file loaded
    var langMan = languageManagerGetDefault()
    var lang = langMan.guessLanguage(filename, nil)
    if lang != nil:
      buffer.setLanguage(lang)
    else:
      buffer.setHighlightSyntax(false)

  # Init tab
  var nTab: Tab; new(nTab)

  # Init the sourceview
  var sourceView: PSourceView
  var scrollWindow: PScrolledWindow
  initSourceView(sourceView, scrollWindow, buffer)

  var nam = name
  if nam == "": nam = "Untitled"
  if filename == "": nam.add(" *")
  elif filename != "" and name == "":
    # Disable the undo/redo manager.
    buffer.begin_not_undoable_action()

    # Read the file first so that we can affirm its encoding.
    try:
      var fileTxt: string = readFile(filename)
      if encoding.toLower() != "utf-8":
        fileTxt = convert(fileTxt, "UTF-8", encoding)
      if not g_utf8_validate(fileTxt, fileTxt.len().gssize, nil):
        win.tempStuff.pendingFilename = filename
        win.statusbar.setTemp("Could not open file with " &
                              encoding & " encoding.", UrgError, 5000)
        win.infobar.show()
        return -1
      # Detect line endings.
      nTab.lineEnding = detectLineEndings(fileTxt)

      # Normalize to LF to fix extra newline after copying issue on Windows.
      fileTxt = normalize(leLf, fileTxt, win.globalSettings.keepEmptyLines)

      # Read in the file.
      buffer.set_text(fileTxt, len(fileTxt).int32)

    except EIO: raise
    finally:
      # Enable the undo/redo manager.
      buffer.end_not_undoable_action()

    # Get the name.ext of the filename, for the tabs title
    nam = extractFilename(filename)

  var (TabLabel, labelText, closeBtn) = createTabLabel(nam, scrollWindow, filename)

  # Add a tab
  nTab.buffer = buffer
  nTab.sourceView = sourceView
  nTab.label = labelText
  nTab.saved = (filename != "")
  nTab.filename = filename
  nTab.closeBtn = closeBtn
  nTab.highlighted = newNoHighlightAll()
  if not win.globalSettings.showCloseOnAllTabs:
    nTab.closeBtn.hide()
  win.tabs.add(nTab)

  # Set the tooltip
  setTabTooltip(win.tabs[win.tabs.len-1])

  # Add the tab to the GtkNotebook
  let res = win.sourceViewTabs.appendPage(scrollWindow, TabLabel)
  assert res != -1
  win.sourceViewTabs.setTabReorderable(scrollWindow, true)

  PTextView(sourceView).setBuffer(nTab.buffer)

  # UGLY workaround for yet another compiler bug:
  discard gsignalConnect(buffer, "mark-set",
                         GCallback(aporia.cursorMoved), nil)

  discard gsignalConnect(buffer, "modified-changed",
                         GCallback(onModifiedChanged),
                         cast[gpointer](win.tabs[win.tabs.len-1]))

  # TODO: If the following gets called at any time because text was loaded from a file,
  # use connect_after to connect "insert-text" signal, and then connect this signal
  # in the handler of "insert-text".
  discard gsignalConnect(buffer, "changed", GCallback(aporia.onChanged), sourceView)

  # Adjustment signals for scrolling past bottom.
  if win.globalSettings.scrollPastBottom:
    discard sourceView.get_vadjustment().signalConnect("value_changed",
        SIGNALFUNC(sourceView_Adjustment_valueChanged), addr nTab.spbInfo)
    discard sourceView.signalConnect("size-allocate",
        SIGNALFUNC(sourceView_sizeAllocate), addr nTab.spbInfo)

  if setCurrent:
    # Select the newly created tab
    win.sourceViewTabs.setCurrentPage(int32(win.tabs.len())-1)
  return win.tabs.len()-1

# GTK Events Contd.
# -- TopMenu & TopBar

proc recentFile_Activate(menuItem: PMenuItem, file: gpointer)
proc fileMenuItem_Activate(menu: PMenuItem, user_data: Pgpointer) =
  if win.tempStuff.recentFileMenuItems.len > 0:
    for i in win.tempStuff.recentFileMenuItems:
      PWidget(i).destroy()

  win.tempStuff.recentFileMenuItems = @[]

  const insertOffset = 7

  # Recently opened files
  # -- Show first ten in the File menu
  if win.autoSettings.recentlyOpenedFiles.len > 0:
    let recent = win.autoSettings.recentlyOpenedFiles

    var moreMenu = menuNew()
    var moreMenuItem = menuItemNew("More recent files...")
    if recent.len > 10:
      moreMenuItem.setSubMenu(moreMenu)
      moreMenuItem.show()
    else:
      PWidget(moreMenu).destroy()
      PWidget(moreMenuItem).destroy()

    let frm = max(0, (recent.len-1)-19)
    let to  = recent.len-1
    var addedItems = 0
    # Countdown from the last item going back to the first, only 10 though.
    for i in countdown(to, frm):
      # Add to the File menu.
      var recentFileMI = menuItemNew($(addedItems+1) & ". " &
                                     recent[i].extractFilename)
      win.tempStuff.recentFileMenuItems.add(recentFileMI)
      if addedItems >= 10:
        # Add to the "More recent files" menu.
        moreMenu.append(recentFileMI)
      else:
        win.FileMenu.insert(recentFileMI, gint(insertOffset+addedItems))
      show(recentFileMI)

      discard signal_connect(recentFileMI, "activate",
                             SIGNAL_FUNC(recentFile_Activate),
                       cast[gpointer](win.autoSettings.recentlyOpenedFiles[i]))
      addedItems.inc()

    if recent.len > 10:
      win.FileMenu.insert(moreMenuItem, gint(insertOffset+10))
      win.tempStuff.recentFileMenuItems.add(moreMenuItem)

proc newFile(menuItem: PMenuItem, user_data: pointer) = discard addTab("", "", true)

proc openFile(menuItem: PMenuItem, user_data: pointer) =
  var startpath = ""
  var currPage = win.sourceViewTabs.getCurrentPage()
  if currPage <% win.tabs.len:
    startpath = os.splitFile(win.tabs[currPage].filename).dir

  if startpath.len == 0:
    # Use lastSavePath as the startpath
    startpath = win.tempStuff.lastSaveDir
    if isNil(startpath) or startpath.len == 0:
      startpath = os.getHomeDir()

  var files = chooseFilesToOpen(win.w, startpath)
  if files.len() > 0:
    for f in items(files):
      try:
        discard addTab("", f, true)
      except EIO:
        error(win.w, "Unable to read from file: " & getCurrentExceptionMsg())

proc saveFile_Activate(menuItem: PMenuItem, user_data: pointer) =
  var current = win.sourceViewTabs.getCurrentPage()
  var startpath = os.splitFile(win.tabs[current].filename).dir
  if startpath == "":
    startpath = win.tempStuff.lastSaveDir

  saveTab(current, startpath)

proc saveFileAs_Activate(menuItem: PMenuItem, user_data: pointer) =
  var current = win.sourceViewTabs.getCurrentPage()
  var startpath = os.splitFile(win.tabs[current].filename).dir
  if startpath == "":
    startpath = win.tempStuff.lastSaveDir
  discard saveTabAs(current, startpath)

proc saveAll_Activate(menuItem: PMenuItem, user_data: pointer) =
  saveAllTabs()

proc closeCurrentTab_Activate(menuItem: PMenuItem, user_data: pointer) =
  closeTab(win.sourceViewTabs.getCurrentPage())

proc closeAllTabs_Activate(menuItem: PMenuItem, user_data: pointer) =
  while win.tabs.len() > 0:
    closeTab(win.sourceViewTabs.getCurrentPage())

proc recentFile_Activate(menuItem: PMenuItem, file: gpointer) =
  let filename = cast[string](file)
  try:
    discard addTab("", filename, true)
  except EIO:
    error(win.w, "Unable to read from file: " & getCurrentExceptionMsg())

proc undo(menuItem: PMenuItem, user_data: pointer) =
  var current = win.sourceViewTabs.getCurrentPage()
  if win.tabs[current].buffer.canUndo():
    win.tabs[current].buffer.undo()
  else:
    win.statusbar.setTemp("Nothing to undo.", UrgError, 5000)
  win.scrollToInsert()

proc redo(menuItem: PMenuItem, user_data: pointer) =
  var current = win.sourceViewTabs.getCurrentPage()
  if win.tabs[current].buffer.canRedo():
    win.tabs[current].buffer.redo()
  else:
    win.statusbar.setTemp("Nothing to redo.", UrgError, 5000)
  win.scrollToInsert()

proc setFindField() =
  # Get the selected text, and set the findEntry to it.
  var currentTab = win.sourceViewTabs.getCurrentPage()
  var insertIter: TTextIter
  win.tabs[currentTab].buffer.getIterAtMark(addr(insertIter),
                                      win.tabs[currentTab].buffer.getInsert())
  var insertOffset = getOffset(addr insertIter)

  var selectIter: TTextIter
  win.tabs[currentTab].buffer.getIterAtMark(addr(selectIter),
                win.tabs[currentTab].buffer.getSelectionBound())
  var selectOffset = getOffset(addr selectIter)

  if insertOffset != selectOffset:
    var text = win.tabs[currentTab].buffer.getText(addr(insertIter),
                                                   addr(selectIter), false)
    win.findEntry.setText(text)

proc find_Activate(menuItem: PMenuItem, user_data: pointer) =
  setFindField()

  win.findBar.show()
  win.findEntry.grabFocus()
  win.replaceEntry.hide()
  win.replaceLabel.hide()
  win.replaceBtn.hide()
  win.replaceAllBtn.hide()

proc replace_Activate(menuitem: PMenuItem, user_data: pointer) =
  setFindField()

  win.findBar.show()
  win.findEntry.grabFocus()
  win.replaceEntry.show()
  win.replaceLabel.show()
  win.replaceBtn.show()
  win.replaceAllBtn.show()

proc findNext_Activate(menuitem: PMenuItem, user_data: pointer) =
  findText(win, true)

proc findPrevious_Activate(menuitem: PMenuItem, user_data: pointer) =
  findText(win, false)

proc GoLine_Activate(menuitem: PMenuItem, user_data: pointer) =
  win.goLineBar.bar.show()
  win.goLineBar.entry.grabFocus()

proc CommentLines_Activate(menuitem: PMenuItem, user_data: pointer) =
  template cb(): expr = win.tabs[currentPage].buffer
  var currentPage = win.sourceViewTabs.getCurrentPage()
  var start, theEnd: TTextIter
  proc toggleSingle() =
    cb.beginUserAction()
    # start and end are the same line no.
    # get the whole
    var line = cb.getText(addr(start), addr(theEnd),
                  false)
    if not (addr theEnd).ends_line:
      discard (addr theEnd).forward_to_line_end
      line = cb.getText(addr(start), addr(theEnd),
                    false)
    # Find first non-whitespace
    var locNonWS = ($line).skipWhitespace()
    # Check if the line is commented.
    let lineComment = win.tempStuff.commentSyntax.line
    if ($line)[locNonWS .. locNonWS+lineComment.len-1] == lineComment:
      # Line is commented
      var startCmntIter, endCmntIter: TTextIter
      var comlen = gint(locNonWS+lineComment.len)
      if ($line)[locNonWS+lineComment.len] == ' ':
        comlen=comlen+1
      cb.getIterAtLineOffset(addr(startCmntIter), (addr start).getLine(),
                             locNonWS.gint)
      cb.getIterAtLineOffset(addr(endCmntIter), (addr start).getLine(),
                             comlen)
      # Remove comment char(s)
      cb.delete(addr(startCmntIter), addr(endCmntIter))
    else:
      var locNonWSIter: TTextIter
      cb.getIterAtLineOffset(addr(locNonWSIter), (addr start).getLine(),
                             locNonWS.gint)
      # Insert the line comment string.
      cb.insert(addr(locNonWSIter), lineComment & ' ', lineComment.len.gint+1)
    cb.endUserAction()

  proc toggleMultiline() =
    cb.beginUserAction()
    (addr theEnd).moveToEndLine() # Move to end of line.
    var selectedTxt = cb.getText(addr(start), addr(theEnd), false)
    # Check if this language supports block comments.
    let blockStart = win.tempStuff.commentSyntax.blockStart & ' '
    let blockEnd   = ' ' & win.tempStuff.commentSyntax.blockEnd
    if blockStart != "":
      var firstNonWS = ($selectedTxt).skipWhitespace()
      if ($selectedTxt)[firstNonWS .. firstNonWS+blockStart.len-1] == blockStart:
        # Uncommenting here.
        # Find blockEnd:
        var blockEndIndex = ($selectedTxt).rfind(blockEnd)
        if blockEndIndex == -1:
          win.statusbar.setTemp("You need to select the end of the block comment.", UrgError, 5000)
          return
        var startCmntIter, endCmntIter: TTextIter
        # Create the mark for the start of the blockEnd comment string.
        cb.getIterAtOffset(addr(startCmntIter), (addr start).getOffset() +
                 blockEndIndex.gint)
        var blockEndMark = cb.createMark(nil, addr(startCmntIter), false)
        # Get the iterators for the start block of comment.
        cb.getIterAtOffset(addr(startCmntIter), (addr start).getOffset() +
                           firstNonWS.gint)
        cb.getIterAtOffset(addr(endCmntIter), (addr start).getOffset() +
                           gint(firstNonWS+blockStart.len))
        cb.delete(addr(startCmntIter), addr(endCmntIter))

        cb.getIterAtMark(addr(startCmntIter), blockEndMark)
        cb.getIterAtOffset(addr(endCmntIter), (addr startCmntIter).getOffset() +
                           gint(blockEnd.len))
        cb.delete(addr(startCmntIter), addr(endCmntIter))
      else:
        # Commenting selection
        var locNonWSIter: TTextIter
        cb.getIterAtOffset(addr(locNonWSIter), (addr start).getOffset() +
                               firstNonWS.gint)
        # Creating a mark here because the iter will get invalidated
        # when I insert the text.
        var endMark = cb.createMark(nil, addr(theEnd), false)
        # Insert block start and end
        cb.insert(addr(locNonWSIter), blockStart, blockStart.len.gint)
        cb.getIterAtMark(addr(theEnd), endMark)
        cb.insert(addr(theEnd), blockEnd, blockEnd.len.gint)
    else:
      # TODO: Loop through each line and add `lineComment`
      # (# in the case of Nim) to it.
      discard
    cb.endUserAction()

  if win.tempStuff.commentSyntax.line == "" and
     win.tempStuff.commentSyntax.blockStart == "" and
     win.tempStuff.commentSyntax.blockEnd == "":
     win.statusbar.setTemp("No comment syntax for " &
              win.getLanguageName(currentPage) & ".", UrgError)
     return

  if cb.getSelectionBounds(addr(start), addr(theEnd)):
    var startOldLineOffset = (addr start).getLineOffset()

    (addr start).setLineOffset(0) # Move to start of line.
    if (addr start).getLine() == (addr theEnd).getLine() and
       win.tempStuff.commentSyntax.line != "":
      toggleSingle()
    else:
      toggleMultiline()
  else:
    (addr start).setLineOffset(0) # Move to start of line.
    if win.tempStuff.commentSyntax.line != "":
      toggleSingle()
    else:
      toggleMultiline()

proc DeleteLine_Activate(menuitem: PMenuItem, user_data: pointer) =
  ## Callback for the Delete Line menu point. Removes the current line
  ## at the cursor, or all marked lines in case text is selected
  template textBuffer(): expr = win.tabs[currentPage].buffer
  var currentPage = win.sourceViewTabs.getCurrentPage()
  var start, theEnd: TTextIter

  textBuffer.beginUserAction()
  discard textBuffer.getSelectionBounds(addr(start), addr(theEnd))
  (addr start).setLineOffset(0) # Move to start of line
  (addr theEnd).moveToEndLine() # Move to end of line

  # Move cursor either to following or previous line if possible
  if not (addr theEnd).forwardCursorPosition():
    discard (addr start).backwardCursorPosition()

  textBuffer.delete(addr(start), addr(theEnd))

  textBuffer.endUserAction()

proc DuplicateLines_Activate(menuitem: PMenuItem, user_data: pointer) =
  ## Callback for the Duplicate Lines menu point. Duplicates the current/selected line(s)
  template textBuffer(): expr = win.tabs[currentPage].buffer
  var currentPage = win.sourceViewTabs.getCurrentPage()
  var start, theEnd: TTextIter

  textBuffer.beginUserAction()
  discard textBuffer.getSelectionBounds(addr(start), addr(theEnd))
  (addr start).setLineOffset(0) # Move to start of line
  (addr theEnd).moveToEndLine() # Move to end of line

  var text: string = "\n" & $textBuffer.getText(addr(start), addr(theEnd), false)
  textBuffer.insert(addr(theEnd), text, text.len.gint)
  textBuffer.endUserAction()

proc settings_Activate(menuitem: PMenuItem, user_data: pointer) =
  settings.showSettings(win)

proc viewToolBar_Toggled(menuitem: PCheckMenuItem, user_data: pointer) =
  win.globalSettings.toolBarVisible = menuitem.itemGetActive()
  if win.globalSettings.toolBarVisible:
    win.toolBar.show()
  else:
    win.toolBar.hide()

proc viewBottomPanel_Toggled(menuitem: PCheckMenuItem, user_data: pointer) =
  win.autoSettings.bottomPanelVisible = menuitem.itemGetActive()
  if win.autoSettings.bottomPanelVisible:
    win.bottomPanelTabs.show()
  else:
    win.bottomPanelTabs.hide()

proc pl_Toggled(menuitem: PCheckMenuItem, id: cstring) =
  if not win.tempStuff.stopPLToggle:
    # TODO: Consider using onclick event instead of variables...

    # Stop from toggling to no language.
    if not menuitem.itemGetActive():
      win.tempStuff.stopPLToggle = true
      menuitem.itemSetActive(true)
      win.tempStuff.stopPLToggle = false
      return

    let currentTab = win.getCurrentTab()
    if id == "":
      win.setHighlightSyntax(currentTab, false)
    else:
      var langMan = languageManagerGetDefault()
      win.setHighlightSyntax(currentTab, true)
      win.setLanguage(currentTab, langMan.getLanguage(id))

    setTabTooltip(win.tabs[currentTab])

    plCheckUpdate(currentTab)

proc showBottomPanel() =
  if not win.autoSettings.bottomPanelVisible:
    win.bottomPanelTabs.show()
    win.autoSettings.bottomPanelVisible = true
    PCheckMenuItem(win.viewBottomPanelMenuItem).itemSetActive(true)

proc saveForCompile(currentTab: int): string =
  if win.tabs[currentTab].filename.len == 0:
    # Save to /tmp
    if not existsDir(getTempDir() / "aporia"): createDir(getTempDir() / "aporia")
    result = getTempDir() / "aporia" / "a" & ($currentTab).addFileExt("nim")
    win.tabs[currentTab].filename = result
    if win.globalSettings.compileUnsavedSave:
      saveTab(currentTab, os.splitFile(win.tabs[currentTab].filename).dir, true)
    else:
      saveTab(currentTab, os.splitFile(win.tabs[currentTab].filename).dir, false)
      win.tabs[currentTab].filename = ""
      win.tabs[currentTab].saved = false

  else:
    saveTab(currentTab, os.splitFile(win.tabs[currentTab].filename).dir)
    result = win.tabs[currentTab].filename
  # Save all tabs which have a filename
  if win.globalSettings.compileSaveAll:
    for i in 0..high(win.tabs):
      if win.tabs[i].filename != "":
        saveTab(i, os.splitFile(win.tabs[i].filename).dir)

proc supportedLang(): bool =
  result = false
  let currentLang = win.getCurrentLanguage()
  if currentLang  == "nim": return true
  win.statusbar.setTemp("Unable to determine what action to take for " &
                        currentLang, UrgError, 5000)


proc compileRun(filename: string, shouldRun: bool) =
  # N.B. Must return when filename is "", CompileProject depends on this behaviour.
  if filename.len == 0: return
  if win.tempStuff.currentExec != nil:
    win.statusbar.setTemp("Process already running!", UrgError, 5000)
    return

  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()

  var cmd = win.getCmd(win.globalSettings.nimCmd, filename)

  # Execute the compiled application if compiled successfully.
  # ifSuccess is the filename of the compiled app.
  var runAfter: PExecOptions = nil
  let workDir = filename.splitFile.dir
  if shouldRun:
    let ifSuccess = changeFileExt(filename, os.ExeExt)
    runAfter = newExec(ifSuccess.quoteIfContainsWhite(), workDir, ExecRun)
  win.execProcAsync newExec(cmd, workDir, ExecNim, runAfter = runAfter)

proc CompileCurrent_Activate(menuitem: PMenuItem, user_data: pointer) =
  if not supportedLang(): return
  let filename = saveForCompile(win.sourceViewTabs.getCurrentPage())
  compileRun(filename, false)

proc CompileRunCurrent_Activate(menuitem: PMenuItem, user_data: pointer) =
  if not supportedLang(): return
  let filename = saveForCompile(win.sourceViewTabs.getCurrentPage())
  compileRun(filename, true)

proc prepareProjectCompile(): string =
  let tabDir = win.tabs[getCurrentTab(win)].filename.splitFile.dir
  let (projectFile, cfgFile) = findProjectFile(tabDir)
  if projectFile == "":
    win.statusbar.setTemp("Could not find project file for currently selected tab.",
        UrgError, 5000)
    return ""
  let projectDir = projectFile.splitFile.dir
  for i in 0..win.tabs.len-1:
    if win.tabs[i].filename.splitFile.dir == projectDir:
      doAssert saveForCompile(i) == win.tabs[i].filename
  return projectFile

proc CompileProject_Activate(menuitem: PMenuItem, user_data: pointer) =
  if not supportedLang(): return
  compileRun(prepareProjectCompile(), false)

proc CompileRunProject_Activate(menuitem: PMenuItem, user_data: pointer) =
  if not supportedLang(): return
  compileRun(prepareProjectCompile(), true)

proc StopProcess_Activate(menuitem: PMenuItem, user_data: pointer) =
  if win.tempStuff.currentExec != nil and
     win.tempStuff.execProcess != nil:
    echod("Terminating process... ID: ", $win.tempStuff.idleFuncId)
    win.tempStuff.execProcess.terminate()
    win.tempStuff.execProcess.close()
    #assert gSourceRemove(win.tempStuff.idleFuncId)
    # currentExec is set to nil in the idle proc. It must be this way.
    # Because otherwise EvStopped stays in the channel.

    var errorTag = createColor(win.outputTextView, "errorTag", "red")
    win.outputTextView.addText("> Process terminated\n", errorTag)
  else:
    win.statusbar.setTemp("No process running.", UrgError, 5000)

proc RunCustomCommand(cmd: string) =
  if win.tempStuff.currentExec != nil:
    win.statusbar.setTemp("Process already running!", UrgError, 5000)
    return

  saveFile_Activate(nil, nil)
  var currentTab = win.sourceViewTabs.getCurrentPage()
  if win.tabs[currentTab].filename.len == 0 or cmd.len == 0: return

  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()

  let workDir = win.tabs[currentTab].filename.splitFile.dir

  win.execProcAsync(
    newExec(win.getCmd(cmd, win.tabs[currentTab].filename), workDir, ExecCustom))

proc RunCustomCommand1(menuitem: PMenuItem, user_data: pointer) =
  RunCustomCommand(win.globalSettings.customCmd1)

proc RunCustomCommand2(menuitem: PMenuItem, user_data: pointer) =
  RunCustomCommand(win.globalSettings.customCmd2)

proc RunCustomCommand3(menuitem: PMenuItem, user_data: pointer) =
  RunCustomCommand(win.globalSettings.customCmd3)

proc RunCheck(menuItem: PMenuItem, user_data: pointer) =
  let filename = saveForCompile(win.sourceViewTabs.getCurrentPage())
  if filename.len == 0: return
  if win.tempStuff.currentExec != nil:
    win.statusbar.setTemp("Process already running!", UrgError, 5000)
    return

  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()

  var cmd = win.getCmd("$findExe(nim) check --listFullPaths $#", filename)
  win.execProcAsync newExec(cmd, "", ExecNim)

proc memUsage_click(menuitem: PMenuItem, user_data: pointer) =
  echod("Memory usage: ")
  gMemProfile()
  var stats = "Memory usage: "
  stats.add GC_getStatistics()
  win.w.info(stats)

proc about_click(menuitem: PMenuItem, user_data: pointer) =
  # About dialog
  var aboutDialog = newAboutDialog("Aporia " & aporiaVersion,
      "Aporia is an IDE for the \nNim programming language.",
      "Copyright (c) 2010-2015 Dominik Picheta")
  aboutDialog.show()

# -- Infobar
proc InfoBar_Response(infobar: PInfoBar, respID: gint, cb: pointer) =
  # (Encodings) info bar button pressed.
  var comboBox = cast[PComboBoxText](cb)
  assert win.tempStuff.pendingFilename != ""
  case respID
  of ResponseOK:
    let active = comboBox.getActive().int
    assert active >= 0 and active <= UTF16LE.int
    comboBox.setActive(0) # Reset selection.
    infobar.hide()
    discard addTab("", win.tempStuff.pendingFilename, true,
           $TEncodingsAvailable(active))
    # addTab may set pendingFilename so we can't reset it here.
    # bad things shouldn't happen if it doesn't get reset though.
  of ResponseCancel:
    comboBox.setActive(0) # Reset selection.
    win.tempStuff.pendingFilename = ""
    infobar.hide()
  else: assert false

# -- sourceViewTabs - Notebook.

proc onCloseTab(btn: PButton, child: PWidget) =
  if win.sourceViewTabs.getNPages() > 1:
    closeTab(win.sourceViewTabs.pageNum(child))

proc tab_buttonRelease(widg: PWidget, ev: PEventButton,
                       userDat: PWidget): gboolean =
  if ev.button == 2: # Middle click.
    closeTab(win.sourceViewTabs.pageNum(userDat))

proc onTabsPressed(widg: PWidget, ev: PEventButton,
                       userDat: PWidget): gboolean =
  if ev.button == 1 and ev.`type` == BUTTON2_PRESS:
    let galloc = win.tabs[win.tabs.len-1].closeBtn.allocation
    if galloc.x == -1:
      # Use the label x instead
      let labelAlloc = win.tabs[win.tabs.len-1].label.allocation
      if labelAlloc.x == -1: return # Last tab's label isn't realized?
      if ev.x < labelAlloc.x.float: return # Didn't click on empty space.
    else:
      if ev.x < galloc.x.float: return # Didn't click on empty space.

    discard addTab("", "", true)

proc onSwitchTab(notebook: PNotebook, page: PNotebookPage, pageNum: guint,
                 user_data: Pgpointer) =
  # hide close button of last active tab
  if not win.globalSettings.showCloseOnAllTabs and
      win.tempStuff.lastTab < win.tabs.len:
    win.tabs[win.tempStuff.lastTab].closeBtn.hide()

  win.tempStuff.lastTab = pageNum
  updateMainTitle(pageNum)
  updateStatusBar(win.tabs[pageNum].buffer)
  # Set the lastSavedDir
  if win.tabs.len > pageNum:
    if win.tabs[pageNum].filename.len != 0:
      win.tempStuff.lastSaveDir = splitFile(win.tabs[pageNum].filename).dir

  # Hide the suggest dialog
  win.suggest.hide()

  if not win.globalSettings.showCloseOnAllTabs:
    # Show close button of tab
    win.tabs[pageNum].closeBtn.show()

  # Get info about the current tabs language. Comment syntax etc.
  win.getCurrentLanguageComment(win.tempStuff.commentSyntax, pageNum)
  # Toggle the "Syntax Highlighting" check menu item based in the new tabs
  # syntax highlighting.
  plCheckUpdate(pageNum)

proc onDragDataReceived(widget: PWidget, context: PDragContext,
                        x: gint, y: gint, data: PSelectionData, info: guint,
                        time: guint, userData: pointer) =
  echod "dragDataReceived: ", $widget.getName()
  var success = false
  if data != nil and data.length >= 0:
    if info == 0:
      var sdata = cast[cstring](data.data)
      for line in `$`(sdata).splitLines():
        if line != "" and line.startswith("file://"):
          var path = line[7 .. ^1]
          echod(path)
          var existingTab = win.findTab(path)
          if existingTab != -1:
            win.sourceViewTabs.setCurrentPage(int32(existingTab))
          else:
            discard addTab("", path, true)
      success = true
    else: echod("dragDataReceived: Unknown `info`")

  dragFinish(context, success, false, time)

proc onPageReordered(notebook: PNotebook, child: PWidget, pageNum: cuint,
                     userData: pointer) =
  let oldPos = win.tabs[win.tempStuff.lastTab]
  system.delete(win.tabs, win.tempStuff.lastTab)
  win.tabs.insert(oldPos, int(pageNum))

  win.tempStuff.lastTab = int(pageNum)

# -- Bottom tabs

proc errorList_RowActivated(tv: PTreeView, path: PTreePath,
            column: PTreeViewColumn, d: pointer) =
  let selectedIndex = path.getIndices()[]
  let item = win.tempStuff.errorList[selectedIndex]
  if item.file == "":
    win.statusbar.setTemp("Could not find correct tab.", UrgError, 5000)
    return
  var existingTab = addTab("", item.file, true)
  if existingTab == -1:
    assert (not existsFile(item.file))

    win.statusbar.setTemp(item.file & " does not exist.", UrgError, 5000)
    return

  # Move cursor to where the error is.
  var line = item.line.parseInt-1
  var insertIndex = int32(item.column.parseInt)-1
  var selectionBound = int32(item.column.parseInt)
  if insertIndex < 0:
    insertIndex = 0
    selectionBound = 1

  # Validate that this line/col combo is not outside bounds
  var endIter: TTextIter
  win.tabs[existingTab].buffer.getEndIter(addr(endIter))
  let lastLine = getLine(addr(endIter))
  if line > lastLine:
    line = lastLine

  var colEndAtLine: TTextIter
  win.tabs[existingTab].buffer.getIterAtLine(addr(colEndAtLine), line.gint)
  moveToEndLine(addr(colEndAtLine))
  let lastColumnAtLine = getLineOffset(addr(colEndAtLine))
  if selectionBound > lastColumnAtLine:
    win.statusbar.setTemp("Line " & $(line+1) & " and column " & $selectionBound &
                          " is outside the bounds of the available text.",
                          UrgError, 5000)
    return

  var iter: TTextIter
  var iterPlus1: TTextIter
  win.tabs[existingTab].buffer.getIterAtLineOffset(addr(iter),
      line.int32, insertIndex)
  win.tabs[existingTab].buffer.getIterAtLineOffset(addr(iterPlus1),
      line.int32, selectionBound)

  win.tabs[existingTab].buffer.selectRange(addr(iter), addr(iterPlus1))

  # TODO: This should be getting focus, but as usual it's not... FIXME
  # TODO: This can perhaps be done by providing a 'initialised' signal, once
  # the scrolling occurs ... look down.
  win.tabs[existingTab].sourceView.grabFocus()

  win.forceScrollToInsert(int32(existingTab))

# -- FindBar

proc nextBtn_Clicked(button: PButton, user_data: Pgpointer) =
  findText(win, true)
proc prevBtn_Clicked(button: PButton, user_data: Pgpointer) =
  findText(win, false)

proc replaceBtn_Clicked(button: PButton, user_data: Pgpointer) =
  var currentTab = win.sourceViewTabs.getCurrentPage()
  var start, theEnd: TTextIter
  if not win.tabs[currentTab].buffer.getSelectionBounds(
        addr(start), addr(theEnd)):
    # If no text is selected, try finding a match.
    findText(win, true)
    if not win.tabs[currentTab].buffer.getSelectionBounds(
          addr(start), addr(theEnd)):
      # No match
      return

  win.tabs[currentTab].buffer.beginUserAction()
  # Remove the text
  win.tabs[currentTab].buffer.delete(addr(start), addr(theEnd))
  # Insert the replacement
  var text = getText(win.replaceEntry)
  win.tabs[currentTab].buffer.insert(addr(start), text, int32(len(text)))

  win.tabs[currentTab].buffer.endUserAction()

  # Find next match, this is just a convenience.
  findText(win, true)

proc replaceAllBtn_Clicked(button: PButton, user_data: Pgpointer) =
  var find = getText(win.findEntry)
  var replace = getText(win.replaceEntry)
  var count = replaceAll(win, find, replace)
  win.statusbar.setTemp("Replaced $1 matches." % $count, UrgNormal, 5000)

proc closeBtn_Clicked(button: PButton, user_data: Pgpointer) =
  win.findBar.hide()

proc caseSens_Changed(radiomenuitem: PRadioMenuitem, user_data: Pgpointer) =
  win.autoSettings.search = SearchCaseSens
proc caseInSens_Changed(radiomenuitem: PRadioMenuitem, user_data: Pgpointer) =
  win.autoSettings.search = SearchCaseInsens
proc style_Changed(radiomenuitem: PRadioMenuitem, user_data: Pgpointer) =
  win.autoSettings.search = SearchStyleInsens
proc regex_Changed(radiomenuitem: PRadioMenuitem, user_data: Pgpointer) =
  win.autoSettings.search = SearchRegex
proc peg_Changed(radiomenuitem: PRadioMenuitem, user_data: Pgpointer) =
  win.autoSettings.search = SearchPeg

proc extraBtn_Clicked(button: PButton, user_data: Pgpointer) =
  var extraMenu = menuNew()
  var group: PGSList

  var caseSensMenuItem = radio_menu_item_new(group, "Case sensitive")
  extraMenu.append(caseSensMenuItem)
  discard signal_connect(caseSensMenuItem, "toggled",
                          SIGNAL_FUNC(caseSens_Changed), nil)
  caseSensMenuItem.show()
  group = caseSensMenuItem.itemGetGroup()

  var caseInSensMenuItem = radio_menu_item_new(group, "Case insensitive")
  extraMenu.append(caseInSensMenuItem)
  discard signal_connect(caseInSensMenuItem, "toggled",
                          SIGNAL_FUNC(caseInSens_Changed), nil)
  caseInSensMenuItem.show()
  group = caseInSensMenuItem.itemGetGroup()

  var styleMenuItem = radio_menu_item_new(group, "Style insensitive")
  extraMenu.append(styleMenuItem)
  discard signal_connect(styleMenuItem, "toggled",
                          SIGNAL_FUNC(style_Changed), nil)
  styleMenuItem.show()
  group = styleMenuItem.itemGetGroup()

  var regexMenuItem = radio_menu_item_new(group, "Regex")
  extraMenu.append(regexMenuItem)
  discard signal_connect(regexMenuItem, "toggled",
                          SIGNAL_FUNC(regex_Changed), nil)
  regexMenuItem.show()
  group = regexMenuItem.itemGetGroup()

  var pegMenuItem = radio_menu_item_new(group, "Pegs")
  extraMenu.append(pegMenuItem)
  discard signal_connect(pegMenuItem, "toggled",
                          SIGNAL_FUNC(peg_Changed), nil)
  pegMenuItem.show()

  # Make the correct radio button active
  case win.autoSettings.search
  of SearchCaseSens:
    PCheckMenuItem(caseSensMenuItem).itemSetActive(true)
  of SearchCaseInsens:
    PCheckMenuItem(caseInSensMenuItem).itemSetActive(true)
  of SearchStyleInsens:
    PCheckMenuItem(styleMenuItem).itemSetActive(true)
  of SearchRegex:
    PCheckMenuItem(regexMenuItem).itemSetActive(true)
  of SearchPeg:
    PCheckMenuItem(pegMenuItem).itemSetActive(true)

  extraMenu.popup(nil, nil, nil, nil, 0, get_current_event_time())

# Go to line bar.
proc goLine_Changed(ed: PEditable, d: Pgpointer) =
  var line = win.goLineBar.entry.getText()
  var lineNum: BiggestInt = -1
  if parseBiggestInt($line, lineNum) != 0:
    # Get current tab
    var current = win.sourceViewTabs.getCurrentPage()
    template buffer: expr = win.tabs[current].buffer
    if not (lineNum-1 < 0 or (lineNum > buffer.getLineCount())):
      var iter: TTextIter
      buffer.getIterAtLine(addr(iter), int32(lineNum)-1)

      buffer.moveMarkByName("insert", addr(iter))
      buffer.moveMarkByName("selection_bound", addr(iter))
      discard PTextView(win.tabs[current].sourceView).
          scrollToIter(addr(iter), 0.2, false, 0.0, 0.0)

      # Reset entry color.
      win.goLineBar.entry.modifyBase(STATE_NORMAL, nil)
      win.goLineBar.entry.modifyText(STATE_NORMAL, nil)
      return # Success

  # Make entry red.
  var red: gdk2.TColor
  discard colorParse("#ff6666", addr(red))
  var white: gdk2.TColor
  discard colorParse("white", addr(white))

  win.goLineBar.entry.modifyBase(STATE_NORMAL, addr(red))
  win.goLineBar.entry.modifyText(STATE_NORMAL, addr(white))

proc goLineClose_clicked(button: PButton, user_data: Pgpointer) =
  win.goLineBar.bar.hide()

# GUI Initialization

proc loadLanguageSections():
      tables.TOrderedTable[string, seq[PSourceLanguage]] =
  result = initOrderedTable[string, seq[PSourceLanguage]]()
  var langMan = languageManagerGetDefault()
  var languages = langMan.getLanguageIDs()
  for i in 0..len(languages.cstringArrayToSeq)-1:
    var lang = langMan.getLanguage(languages[i])
    assert lang != nil
    if lang.getHidden(): continue
    let section = $lang.getSection()
    if not result.hasKey(section):
      result[section] = @[]
    result.mget(section).add(lang)

  for k, v in mpairs(result):
    v.sort do (x, y: PSourceLanguage) -> int {.closure.}:
      return cmp(toLower($x.getName()), toLower($y.getName()))

  #let cmpB = proc (x, y: tuple[key: string, val: seq[PSourceLanguage]]): int {.closure.} =
  #  return cmp(x.key, y.key)

  #result.sort cmpB

proc initTopMenu(mainBox: PBox) =
  # Create a accelerator group, used for shortcuts
  # like CTRL + S in SaveMenuItem
  var accGroup = accel_group_new()
  add_accel_group(win.w, accGroup)

  # TopMenu(MenuBar)
  var TopMenu = menuBarNew()

  # FileMenu
  win.FileMenu = menuNew()

  # New
  win.FileMenu.createAccelMenuItem(accGroup, "", win.globalSettings.keyNewFile.keyval, newFile, win.globalSettings.keyNewFile.state,
                                   StockNew)
  createSeparator(win.FileMenu)
  win.FileMenu.createAccelMenuItem(accGroup, "", win.globalSettings.keyOpenFile.keyval, openFile, win.globalSettings.keyOpenFile.state,
                                   StockOpen)
  win.FileMenu.createAccelMenuItem(accGroup, "", win.globalSettings.keySaveFile.keyval, saveFile_activate,
                                   win.globalSettings.keySaveFile.state, StockSave)
  win.FileMenu.createAccelMenuItem(accGroup, "", win.globalSettings.keySaveFileAs.keyval, saveFileAs_Activate,
                                   win.globalSettings.keySaveFileAs.state, StockSaveAs)

  win.FileMenu.createAccelMenuItem(accGroup, "Save All", win.globalSettings.keySaveAll.keyval, saveAll_Activate,
                                   win.globalSettings.keySaveAll.state, "")

  createSeparator(win.FileMenu)

  createSeparator(win.FileMenu)

  win.FileMenu.createAccelMenuItem(accGroup, "", win.globalSettings.keyCloseCurrentTab.keyval, closeCurrentTab_Activate,
                                   win.globalSettings.keyCloseCurrentTab.state, StockClose)
  win.FileMenu.createAccelMenuItem(accGroup, "Close All", win.globalSettings.keyCloseAllTabs.keyval, closeAllTabs_Activate,
                                   win.globalSettings.keyCloseAllTabs.state, "")

  createSeparator(win.FileMenu)
  let quitAporia =
    proc (menuItem: PMenuItem, user_data: pointer) =
      if not deleteEvent(menuItem, nil, nil):
        aporia.exit()
  win.FileMenu.createAccelMenuItem(accGroup, "", win.globalSettings.keyQuit.keyval,
    quitAporia, win.globalSettings.keyQuit.state,  StockQuit)

  var FileMenuItem = menuItemNewWithMnemonic("_File")
  discard signalConnect(FileMenuItem, "activate",
                        SIGNAL_FUNC(fileMenuItem_Activate), nil)

  FileMenuItem.setSubMenu(win.FileMenu)
  FileMenuItem.show()
  TopMenu.append(FileMenuItem)

  # Edit menu
  var EditMenu = menuNew()

  # Undo/Redo
  EditMenu.createImageMenuItem(STOCK_UNDO, aporia.undo)
  EditMenu.createImageMenuItem(STOCK_Redo, aporia.redo)
  createSeparator(EditMenu)
  EditMenu.createAccelMenuItem(accGroup, "Comment/Uncomment Line(s)", win.globalSettings.keyCommentLines.keyval,
      CommentLines_Activate, win.globalSettings.keyCommentLines.state, "")
  EditMenu.createAccelMenuItem(accGroup, "Delete Line", win.globalSettings.keyDeleteLine.keyval,
      DeleteLine_Activate, win.globalSettings.keyDeleteLine.state, "")
  EditMenu.createAccelMenuItem(accGroup, "Duplicate Line(s)", win.globalSettings.keyDuplicateLines.keyval,
      DuplicateLines_Activate, win.globalSettings.keyDuplicateLines.state, "")
  createSeparator(EditMenu)

  EditMenu.createMenuItem("Raw Preferences",
    proc (i: PMenuItem, p: pointer) {.cdecl.} =
      try:
        discard addTab("", joinPath(os.getConfigDir(), "Aporia", "config.global.ini"))
      except EIO:
        win.statusBar.setTemp(getCurrentExceptionMsg(), UrgError)
  )


  # Settings
  EditMenu.createImageMenuItem(StockPreferences, aporia.settings_Activate)
  var EditMenuItem = menuItemNewWithMnemonic("_Edit")
  EditMenuItem.setSubMenu(EditMenu)
  EditMenuItem.show()
  TopMenu.append(EditMenuItem)

  # Search menu
  var SearchMenu = menuNew()
  # Find/Find & Replace
  SearchMenu.createAccelMenuItem(accGroup, "", win.globalSettings.keyFind.keyval, aporia.find_Activate,
      win.globalSettings.keyFind.state, StockFind)
  SearchMenu.createAccelMenuItem(accGroup, "", win.globalSettings.keyReplace.keyval, aporia.replace_Activate,
      win.globalSettings.keyReplace.state, StockFindAndReplace)
  SearchMenu.createAccelMenuItem(accGroup, "Next", win.globalSettings.keyFindNext.keyval, aporia.findNext_Activate,
      0, "")
  SearchMenu.createAccelMenuItem(accGroup, "Previous", win.globalSettings.keyFindPrevious.keyval, aporia.findPrevious_Activate,
      0, "")

  createSeparator(SearchMenu)
  SearchMenu.createAccelMenuItem(accGroup, "Go to line...", win.globalSettings.keyGoToLine.keyval,
      GoLine_Activate, win.globalSettings.keyGoToLine.state, "")
  SearchMenu.createAccelMenuItem(accGroup, "Go to definition under cursor", win.globalSettings.keyGoToDef.keyval,
      goToDef_Activate, win.globalSettings.keyGoToDef.state)
  var SearchMenuItem = menuItemNewWithMnemonic("_Search")
  SearchMenuItem.setSubMenu(SearchMenu)
  SearchMenuItem.show()
  TopMenu.append(SearchMenuItem)

  # View menu
  var ViewMenu = menuNew()

  win.viewToolBarMenuItem = check_menu_item_new("Tool Bar")
  PCheckMenuItem(win.viewToolBarMenuItem).itemSetActive(
         win.globalSettings.toolBarVisible)
  ViewMenu.append(win.viewToolBarMenuItem)
  show(win.viewToolBarMenuItem)
  discard signal_connect(win.viewToolBarMenuItem, "toggled",
                          SIGNAL_FUNC(aporia.viewToolBar_Toggled), nil)

  win.viewBottomPanelMenuItem = check_menu_item_new("Bottom Panel")
  PCheckMenuItem(win.viewBottomPanelMenuItem).itemSetActive(
         win.autoSettings.bottomPanelVisible)
  win.viewBottomPanelMenuItem.add_accelerator("activate", accGroup,
         win.globalSettings.keyToggleBottomPanel.keyval, win.globalSettings.keyToggleBottomPanel.state, ACCEL_VISIBLE)
  ViewMenu.append(win.viewBottomPanelMenuItem)
  show(win.viewBottomPanelMenuItem)
  discard signal_connect(win.viewBottomPanelMenuItem, "toggled",
                          SIGNAL_FUNC(aporia.viewBottomPanel_Toggled), nil)
  createSeparator(ViewMenu)
  # -- Syntax Highlighting sections

  let langSections = loadLanguageSections()
  win.tempStuff.plMenuItems = initTable[string, tuple[mi: PCheckMenuItem, id: string]]()
  var SyntaxHighlightingMenuItem = menuItemNew("Syntax Highlighting")
  SyntaxHighlightingMenuItem.show()
  var SyntaxHighlightingMenu = menuNew(); SyntaxHighlightingMenu.show()
  SyntaxHighlightingMenuItem.setSubMenu(SyntaxHighlightingMenu)
  ViewMenu.append(SyntaxHighlightingMenuItem)
  # Add plain text.
  var plainTextItem = checkMenuItemNew("Plain text"); plainTextItem.show()
  SyntaxHighlightingMenu.append(plainTextItem)
  win.tempStuff.plMenuItems[""] = (plainTextItem, "")
  var plainText = ""
  GCRef(plainText) # We need this for the whole lifetime of this app
  discard signalConnect(plainTextItem, "toggled",
                        SignalFunc(pl_Toggled),
          addr(plainText[0]))

  for section, langs in langSections:
    var sectionMenuItem = menuItemNew(section); sectionMenuItem.show()
    var sectionMenu = menuNew(); sectionMenu.show()
    sectionMenuItem.setSubMenu(sectionMenu)
    for lang in langs:
      var langMenuItem = checkMenuItemNew(lang.getName()); langMenuItem.show()
      sectionMenu.append(langMenuItem)
      win.tempStuff.plMenuItems[$lang.getID()] = (langMenuItem, $lang.getID())
      var langID = $lang.getID()
      GCRef(langID)
      discard signalConnect(langMenuItem, "toggled",
                            SignalFunc(pl_Toggled),
              addr(langID[0]))
    SyntaxHighlightingMenu.append(sectionMenuItem)

  var ViewMenuItem = menuItemNewWithMnemonic("_View")

  ViewMenuItem.setSubMenu(ViewMenu)
  ViewMenuItem.show()
  TopMenu.append(ViewMenuItem)


  # Tools menu
  var ToolsMenu = menuNew()

  createAccelMenuItem(ToolsMenu, accGroup, "Compile current file",
                      win.globalSettings.keyCompileCurrent.keyval, aporia.CompileCurrent_Activate, win.globalSettings.keyCompileCurrent.state)
  createAccelMenuItem(ToolsMenu, accGroup, "Compile & run current file",
                      win.globalSettings.keyCompileRunCurrent.keyval, aporia.CompileRunCurrent_Activate, win.globalSettings.keyCompileRunCurrent.state)
  createSeparator(ToolsMenu)
  createAccelMenuItem(ToolsMenu, accGroup, "Compile project",
                      win.globalSettings.keyCompileProject.keyval, aporia.CompileProject_Activate, win.globalSettings.keyCompileProject.state)
  createAccelMenuItem(ToolsMenu, accGroup, "Compile & run project",
                      win.globalSettings.keyCompileRunProject.keyval, aporia.CompileRunProject_Activate, win.globalSettings.keyCompileRunProject.state)
  createAccelMenuItem(ToolsMenu, accGroup, "Terminate running process",
                      win.globalSettings.keyStopProcess.keyval, aporia.StopProcess_Activate, win.globalSettings.keyStopProcess.state)
  createSeparator(ToolsMenu)
  createAccelMenuItem(ToolsMenu, accGroup, "Run custom command 1",
                      win.globalSettings.keyRunCustomCommand1.keyval, aporia.RunCustomCommand1, win.globalSettings.keyRunCustomCommand1.state)
  createAccelMenuItem(ToolsMenu, accGroup, "Run custom command 2",
                      win.globalSettings.keyRunCustomCommand2.keyval, aporia.RunCustomCommand2, win.globalSettings.keyRunCustomCommand2.state)
  createAccelMenuItem(ToolsMenu, accGroup, "Run custom command 3",
                      win.globalSettings.keyRunCustomCommand3.keyval, aporia.RunCustomCommand3, win.globalSettings.keyRunCustomCommand3.state)
  createSeparator(ToolsMenu)
  createAccelMenuItem(ToolsMenu, accGroup, "Check",
                      win.globalSettings.keyRunCheck.keyval, aporia.RunCheck, win.globalSettings.keyRunCheck.state)


  var ToolsMenuItem = menuItemNewWithMnemonic("_Tools")

  ToolsMenuItem.setSubMenu(ToolsMenu)
  ToolsMenuItem.show()
  TopMenu.append(ToolsMenuItem)

  # Help menu
  var HelpMenu = menuNew()

  var MemMenuItem = menu_item_new("GTK Memory usage") # GTK Mem usage
  HelpMenu.append(MemMenuItem)
  show(MemMenuItem)
  discard signal_connect(MemMenuItem, "activate",
                         SIGNAL_FUNC(aporia.memUsage_click), nil)

  HelpMenu.createImageMenuItem(StockAbout, aporia.about_click)

  var HelpMenuItem = menuItemNewWithMnemonic("_Help")

  HelpMenuItem.setSubMenu(HelpMenu)
  HelpMenuItem.show()
  TopMenu.append(HelpMenuItem)

  mainBox.packStart(TopMenu, false, false, 0)
  TopMenu.show()

proc initToolBar(mainBox: PBox) =
  # Create top ToolBar
  win.toolBar = toolbarNew()
  win.toolBar.setStyle(TOOLBAR_ICONS)

  discard win.toolBar.insertStock(STOCK_NEW, "New File",
                      "New File", SIGNAL_FUNC(aporia.newFile), nil, 0)
  win.toolBar.appendSpace()
  discard win.toolBar.insertStock(STOCK_OPEN, "Open",
                      "Open", SIGNAL_FUNC(aporia.openFile), nil, -1)
  discard win.toolBar.insertStock(STOCK_SAVE, "Save",
                      "Save", SIGNAL_FUNC(saveFile_Activate), nil, -1)
  win.toolBar.appendSpace()
  discard win.toolBar.insertStock(STOCK_UNDO, "Undo",
                      "Undo", SIGNAL_FUNC(aporia.undo), nil, -1)
  discard win.toolBar.insertStock(STOCK_REDO, "Redo",
                      "Redo", SIGNAL_FUNC(aporia.redo), nil, -1)
  win.toolBar.appendSpace()
  discard win.toolBar.insertStock(STOCK_FIND, "Find",
                      "Find", SIGNAL_FUNC(aporia.find_Activate), nil, -1)

  mainBox.packStart(win.toolBar, false, false, 0)
  if win.globalSettings.toolBarVisible == true:
    win.toolBar.show()

proc initInfoBar(mainBox: PBox) =
  win.infobar = infoBarNewWithButtons(STOCK_OPEN, ResponseOK, STOCK_CANCEL, ResponseCancel, nil)
  win.infobar.setMessageType(MessageInfo)
  var vbox = vboxNew(false, 0);vbox.show()
  let msgText = "File could not be opened because its encoding " &
                         "could not be established."
  var messageLabel = labelNew(nil)
  messageLabel.setUseMarkup(true)
  messageLabel.setMarkup("<span style=\"oblique\" font=\"13.5\">" & msgText &
                         "</span>")
  messageLabel.setAlignment(0.0, 0.5) # Left align.
  messageLabel.show()
  vbox.packStart(messageLabel, false, false, 0)

  var hbox = hboxNew(false, 0); hbox.show()
  var chooseEncodingLabel = labelNew("Choose encoding: ")
  chooseEncodingLabel.setAlignment(0.0, 0.5) # Left align.
  chooseEncodingLabel.show()
  hbox.packStart(chooseEncodingLabel, false, false, 0)

  var encodingsComboBox = comboBoxTextNew()
  encodingsComboBox.appendText($UTF8)
  encodingsComboBox.appendText($ISO88591)
  encodingsComboBox.appendText($GB2312)
  encodingsComboBox.appendText($Windows1251)
  encodingsComboBox.appendText($UTF16BE)
  encodingsComboBox.appendText($UTF16LE)
  encodingsComboBox.setActive(UTF8.guint)
  encodingsComboBox.show()
  hbox.packStart(encodingsComboBox, false, false, 0)

  vbox.packStart(hbox, false, false, 10)
  var contentArea = win.infobar.getContentArea()
  contentArea.add(vbox)

  mainBox.packStart(win.infobar, false, false, 0)

  discard win.infobar.signalConnect("response",
         SIGNAL_FUNC(InfoBarResponse), encodingsComboBox)

proc createTargetEntry(target: string, flags, info: int): TTargetEntry =
  result.target = target
  result.flags = flags.int32
  result.info = info.int32

proc initsourceViewTabs() =
  win.sourceViewTabs = notebookNew()
  discard win.sourceViewTabs.signalConnect(
          "switch-page", SIGNAL_FUNC(onSwitchTab), nil)
  win.sourceViewTabs.set_scrollable(true)

  # Drag and Drop setup
  # TODO: This should only allow files.
  var targetList = createTargetEntry("STRING", 0, 0)

  win.sourceViewTabs.dragDestSet(DEST_DEFAULT_ALL, addr(targetList),
                                 1, ACTION_COPY)
  discard win.sourceViewTabs.signalConnect(
          "drag-data-received", SIGNAL_FUNC(onDragDataReceived), nil)

  discard win.sourceViewTabs.signalConnect("page-reordered",
          SIGNAL_FUNC(onPageReordered), nil)

  discard win.sourceViewTabs.signalConnect("button-press-event",
          SIGNAL_FUNC(onTabsPressed), nil)

  win.sourceViewTabs.show()

  var count = 0

  if win.globalSettings.restoreTabs and lastSession.len > 0:
    for i in 0 .. lastSession.len-1:
      var splitUp = lastSession[i].split('|')
      var (filename, offset) = (splitUp[0], splitUp[1])
      if existsFile(filename):
        let newTab = addTab("", filename, win.autoSettings.lastSelectedTab == filename)
        inc(count)
        if newTab == -1: continue # Error adding tab, ``addTab`` will update the status bar with more info
        var iter: TTextIter
        # TODO: Save last cursor position as line and column offset combo.
        # This will help with int overflows which would happen more often with
        # a char offset.
        win.tabs[newTab].buffer.getIterAtOffset(addr(iter), int32(offset.parseInt()))
        win.tabs[newTab].buffer.placeCursor(addr(iter))

        win.forceScrollToInsert(int32(newTab))

      else: dialogs.error(win.w, "Could not restore file from session, file not found: " & filename)

  for f in loadFiles:
    if existsFile(f):
      var absPath = f
      if not isAbsolute(absPath):
        absPath = getCurrentDir() / f
      discard addTab("", absPath)
      inc(count)
    else:
      dialogs.error(win.w, "Could not open " & f)
      quit(QuitFailure)

  if count == 0:
    discard addTab("", "", false)

proc initBottomTabs() =
  win.bottomPanelTabs = notebookNew()
  if win.autoSettings.bottomPanelVisible:
    win.bottomPanelTabs.show()

  # -- output tab
  var tabLabel = labelNew("Output")
  var outputTab = vboxNew(false, 0)
  discard win.bottomPanelTabs.appendPage(outputTab, tabLabel)
  # Compiler tabs, gtktextview
  var outputScrolledWindow = scrolledwindowNew(nil, nil)
  outputScrolledWindow.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  outputTab.packStart(outputScrolledWindow, true, true, 0)
  outputScrolledWindow.show()

  win.outputTextView = textviewNew()
  outputScrolledWindow.add(win.outputTextView)
  win.outputTextView.show()
  var font = font_description_from_string(win.globalSettings.outputFont)
  win.outputTextView.modifyFont(font)

  # Create a mark at the end of the outputTextView.
  var endIter: TTextIter
  win.outputTextView.getBuffer().getEndIter(addr(endIter))
  discard win.outputTextView.
          getBuffer().createMark("endMark", addr(endIter), false)

  outputTab.show()

  # -- errors tab
  var errorListLabel = labelNew("Error list")
  var errorListTab = vboxNew(false, 0)
  discard win.bottomPanelTabs.appendPage(errorListTab, errorListLabel)

  var errorsScrollWin = scrolledWindowNew(nil, nil)
  errorsScrollWin.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  errorListTab.packStart(errorsScrollWin, true, true, 0)
  errorsScrollWin.show()

  win.errorListWidget = treeviewNew()
  discard win.errorListWidget.signalConnect("row-activated",
              SIGNAL_FUNC(errorList_RowActivated), nil)

  errorsScrollWin.add(win.errorListWidget)

  win.errorListWidget.createTextColumn("File", 0, false, 5)
  win.errorListWidget.createTextColumn("Line", 1, false, 5)
  win.errorListWidget.createTextColumn("Column", 2, false, 5)
  win.errorListWidget.createTextColumn("Type", 3, false, 5)
  win.errorListWidget.createTextColumn("Description", 4, true, 5)
  win.errorListWidget.createTextColumn("Color", 5, false, 5, false)

  var listStore = listStoreNew(6, TypeString, TypeString, TypeString,
                                  TypeString, TypeString, TypeString)
  assert(listStore != nil)
  win.errorListWidget.setModel(liststore)
  win.errorListWidget.show()
  errorListTab.show()

  #addError(TETError, "type mistmatch:\n expected blah\n got: proc asd();",
  #  "file.nim", "190", "5")


proc initTAndBP(mainBox: PBox) =
  # This init's the HPaned, which splits the sourceViewTabs
  # and the BottomPanelTabs
  initsourceViewTabs()
  initBottomTabs()

  var tAndBPVPaned = vpanedNew()
  tandbpVPaned.pack1(win.sourceViewTabs, resize=true, shrink=false)
  tandbpVPaned.pack2(win.bottomPanelTabs, resize=false, shrink=false)
  mainBox.packStart(tAndBPVPaned, true, true, 0)
  tandbpVPaned.setPosition(win.autoSettings.VPanedPos)
  tAndBPVPaned.show()

proc initFindBar(mainBox: PBox) =
  # Create a fixed container
  win.findBar = hBoxNew(false, 0)
  win.findBar.setSpacing(4)

  # Add a Label 'Find'
  var findLabel = labelNew("Find:")
  win.findBar.packStart(findLabel, false, false, 5)
  findLabel.show()

  # Add a (find) text entry
  win.findEntry = entryNew()
  win.findBar.packStart(win.findEntry, true, true, 0)
  # The following event gets fired when Enter is pressed.
  discard win.findEntry.signalConnect("activate", SIGNAL_FUNC(
                                      aporia.nextBtn_Clicked), nil)

  win.findEntry.show()
  var rq: TRequisition
  win.findEntry.sizeRequest(addr(rq))

  # Make the (find) text entry longer
  win.findEntry.set_size_request(190, rq.height)

  # Add a Label 'Replace'
  # - This Is only shown when the 'Search & Replace'(CTRL + H) is shown
  win.replaceLabel = labelNew("Replace:")
  win.findBar.packStart(win.replaceLabel, false, false, 0)

  # Add a (replace) text entry
  # - This Is only shown when the 'Search & Replace'(CTRL + H) is shown
  win.replaceEntry = entryNew()
  win.findBar.packStart(win.replaceEntry, true, true, 0)
  var rq1: TRequisition
  win.replaceEntry.sizeRequest(addr(rq1))

  # Make the (replace) text entry longer
  win.replaceEntry.set_size_request(100, rq1.height)

  # Find next button
  var nextBtn = buttonNew("Next")
  win.findBar.packStart(nextBtn, false, false, 0)
  discard nextBtn.signalConnect("clicked",
             SIGNAL_FUNC(aporia.nextBtn_Clicked), nil)
  nextBtn.show()
  var nxtBtnRq: TRequisition
  nextBtn.sizeRequest(addr(nxtBtnRq))

  # Find previous button
  var prevBtn = buttonNew("Previous")
  win.findBar.packStart(prevBtn, false, false, 0)
  discard prevBtn.signalConnect("clicked",
             SIGNAL_FUNC(aporia.prevBtn_Clicked), nil)
  prevBtn.show()

  # Replace button
  # - This Is only shown when the 'Search & Replace'(CTRL + H) is shown
  win.replaceBtn = buttonNew("Replace")
  win.findBar.packStart(win.replaceBtn, false, false, 0)
  discard win.replaceBtn.signalConnect("clicked",
             SIGNAL_FUNC(aporia.replaceBtn_Clicked), nil)

  # Replace all button
  # - this Is only shown when the 'Search & Replace'(CTRL + H) is shown
  win.replaceAllBtn = buttonNew("Replace All")
  win.findBar.packStart(win.replaceAllBtn, false, false, 0)
  discard win.replaceAllBtn.signalConnect("clicked",
             SIGNAL_FUNC(aporia.replaceAllBtn_Clicked), nil)

  # Right side ...

  # Close button - With a close stock image
  var closeBtn = buttonNew()
  var closeImage = imageNewFromStock(STOCK_CLOSE, ICON_SIZE_SMALL_TOOLBAR)
  var closeBox = hboxNew(false, 0)
  closeBtn.add(closeBox)
  closeBox.show()
  closeBox.add(closeImage)
  closeImage.show()
  discard closeBtn.signalConnect("clicked",
             SIGNAL_FUNC(aporia.closeBtn_Clicked), nil)
  win.findBar.packEnd(closeBtn, false, false, 2)
  closeBtn.show()

  # Extra button - When clicked shows a menu with options like 'Use regex'
  var extraBtn = buttonNew()
  var extraImage = imageNewFromStock(STOCK_PROPERTIES, ICON_SIZE_SMALL_TOOLBAR)

  var extraBox = hboxNew(false, 0)
  extraBtn.add(extraBox)
  extraBox.show()
  extraBox.add(extraImage)
  extraImage.show()
  discard extraBtn.signalConnect("clicked",
             SIGNAL_FUNC(aporia.extraBtn_Clicked), nil)
  win.findBar.packEnd(extraBtn, false, false, 0)
  extraBtn.show()

  mainBox.packStart(win.findBar, false, false, 0)
  #win.findBar.show()

  proc findBar_Hide(widget: PWidget, dummy: gpointer) {.cdecl.} =
    if win.globalSettings.searchHighlightAll:
      stopHighlightAll(win, true)
    else:
      win.tabs[win.getCurrentTab()].highlighted = newNoHighlightAll()

  discard win.findBar.signalConnect("hide",
             SIGNAL_FUNC(findBar_Hide), nil)

proc initGoLineBar(mainBox: PBox) =
  # Create a fixed container
  win.goLineBar.bar = hBoxNew(false, 0)
  win.goLineBar.bar.setSpacing(4)

  # Add a Label 'Go to line'
  var goLineLabel = labelNew("Go to line:")
  win.goLineBar.bar.packStart(goLineLabel, false, false, 5)
  goLineLabel.show()

  # Add a text entry
  win.goLineBar.entry = entryNew()
  win.goLineBar.bar.packStart(win.goLineBar.entry, false, false, 0)
  discard win.goLineBar.entry.signalConnect("changed", SIGNAL_FUNC(
                                      goLine_changed), nil)
  # Go to line also when Return key is pressed:
  discard win.goLineBar.entry.signalConnect("activate", SIGNAL_FUNC(
                                      goLine_changed), nil)
  win.goLineBar.entry.show()

  # Right side ...

  # Close button - With a close stock image
  var closeBtn = buttonNew()
  var closeImage = imageNewFromStock(STOCK_CLOSE, ICON_SIZE_SMALL_TOOLBAR)
  var closeBox = hboxNew(false, 0)
  closeBtn.add(closeBox)
  closeBox.show()
  closeBox.add(closeImage)
  closeImage.show()
  discard closeBtn.signalConnect("clicked",
             SIGNAL_FUNC(aporia.goLineClose_Clicked), nil)
  win.goLineBar.bar.packEnd(closeBtn, false, false, 2)
  closeBtn.show()

  mainBox.packStart(win.goLineBar.bar, false, false, 0)

proc initTempStuff() =
  win.tempStuff.lastSaveDir = ""
  win.tempStuff.stopSBUpdates = false

  win.tempStuff.compileSuccess = false

  win.tempStuff.recentFileMenuItems = @[]

  win.tempStuff.compilationErrorBuffer = ""
  win.tempStuff.errorList = @[]
  win.tempStuff.lastTab = 0
  win.tempStuff.pendingFilename = ""
  win.tempStuff.currentToggledLang = ""

  win.tempStuff.autoComplete = newAutoComplete()

{.pop.}
proc initSocket() =
  win.IODispatcher = newDispatcher()
  win.oneInstSock = asyncSocket()
  win.oneInstSock.handleAccept =
    proc (s: PAsyncSocket) =
      var client: PAsyncSocket
      new(client)
      s.accept(client)
      #FIXME: threadAnalysis is set to off to work around this anonymous proc not being gc safe
      client.handleRead =
        proc (c: PAsyncSocket) {.closure, gcsafe.} =
          var line = ""
          if c.readLine(line):
            if line == "":
              c.close()
            elif line == "\c\L":
              win.w.present()
            else:
              var filePath = line
              if not filePath.isAbsolute():
                filePath = getCurrentDir() / filePath
              if existsFile(filepath):
                discard addTab("", filepath, true)
                win.w.present()
              else:
                win.w.error("File not found: " & filepath)
                win.w.present()
          else:
            win.w.error("One instance socket error on recvLine operation: " & oSErrorMsg(osLastError()))
      win.IODispatcher.register(client)

  win.IODispatcher.register(win.oneInstSock)
  win.oneInstSock.bindAddr(TPort(win.globalSettings.singleInstancePort.toU16), "localhost")
  win.oneInstSock.listen()
{.push cdecl.}

proc initControls() =
  # Load up the language style
  var langMan = languageManagerGetDefault()
  var langManPaths: seq[string] = @[os.getAppDir() / langSpecs]

  var defLangManPaths = langMan.getSearchPath()
  for i in 0..len(defLangManPaths.cstringArrayToSeq)-1:
    if deflangManPaths[i] == nil: echod("[Warning] language manager path is nil")
    langManPaths.add($defLangManPaths[i])

  var newLangPaths = allocCStringArray(langManPaths)
  langMan.setSearchPath(newLangPaths)
  deallocCStringArray(newLangPaths)
  var nimLang = langMan.getLanguage("nim")
  win.nimLang = nimLang

  # Load the scheme
  var schemeMan = schemeManagerGetDefault()
  schemeMan.appendSearchPath(os.getAppDir() / styles)
  win.scheme = schemeMan.getScheme(win.globalSettings.colorSchemeID)

  # Window
  win.w = windowNew(gtk2.WINDOW_TOPLEVEL)
  win.w.setDefaultSize(win.autoSettings.winWidth, win.autoSettings.winHeight)
  win.w.setTitle("Aporia")
  if win.autoSettings.winMaximized: win.w.maximize()

  let winDestroy =
    proc (widget: PWidget, data: Pgpointer) {.cdecl.} =
      aporia.exit()

  discard win.w.signalConnect("destroy", SIGNAL_FUNC(winDestroy), nil)
  discard win.w.signalConnect("delete_event",
    SIGNAL_FUNC(aporia.delete_event), nil)
  discard win.w.signalConnect("window-state-event",
    SIGNAL_FUNC(aporia.windowState_Changed), nil)
  discard win.w.signalConnect("configure-event",
    SIGNAL_FUNC(window_configureEvent), nil)
  discard win.w.signalConnect("key-press-event",
    SIGNAL_FUNC(window_keyPress), nil)

  # Init tempStuff
  initTempStuff()

  # Suggest dialog
  createSuggestDialog(win)

  # mainBox (vbox)
  var mainBox = vboxNew(false, 0)
  win.w.add(mainBox)

  initTopMenu(mainBox)
  initToolBar(mainBox)
  initInfoBar(mainBox)
  initTAndBP(mainBox)
  initFindBar(mainBox)
  initGoLineBar(mainBox)
  #initStatusBar(mainBox)
  win.statusbar = initCustomStatusBar(mainBox)

  mainBox.show()

  # TODO: The fact that this call was above all initializations was because of
  # the VPaned position. I had to move it here because showing the Window
  # before initializing (I presume, could be another widget) the GtkSourceView
  # (maybe the ScrolledView) means that the stupid thing won't scroll on startup.
  # This took me a VERY long time to find.
  win.w.show()

  # Show config errors after the main window is shown
  showConfigErrors()

  # Set focus to text input:
  win.tabs[win.sourceViewTabs.getCurrentPage()].sourceview.grabFocus()

  when not defined(noSingleInstance):
    if win.globalSettings.singleInstance:
      try:
        initSocket()
      except:
        echo getStackTrace()
        dialogs.warning(win.w,
          "Unable to bind socket. Aporia will not " &
          "function properly as a single instance. Error was: " & getCurrentExceptionMsg())
      discard gTimeoutAddFull(glib2.GPriorityDefault, 500,
        proc (dummy: pointer): bool =
          result = win.IODispatcher.poll(5), nil, nil)

proc checkAlreadyRunning(): bool =
  result = false
  var client = socket()
  try:
    client.connect("localhost", TPort(win.globalSettings.singleInstancePort.toU16))
  except EOS:
    return false
  echo("An instance of aporia is already running.")
  if loadFiles.len() > 0:
    for file in loadFiles:
      var filepath = file
      if not filepath.isAbsolute():
        filepath = getCurrentDir() / filepath
      client.send(filepath & "\c\L")
    client.close()
    result = true
  else:
    result = true
    client.send("\c\L")
    client.close()

var versionReply = checkVersion(GTKVerReq[0], GTKVerReq[1], GTKVerReq[2])
if versionReply != nil:
  # Incorrect GTK version.
  quit("Aporia requires GTK $#.$#.$#. Call to check_version failed with: $#" %
       [$GTKVerReq[0], $GTKVerReq[1], $GTKVerReq[2], $versionReply], QuitFailure)

when not defined(noSingleInstance):
  if win.globalSettings.singleInstance:
    if checkAlreadyRunning():
      quit(QuitSuccess)

createProcessThreads(win)
nimrod_init()
initControls()
main()
