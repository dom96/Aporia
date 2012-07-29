#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import glib2, gtk2, gdk2, gtksourceview, dialogs, os, pango, osproc, strutils
import pegs, streams, times, parseopt, parseutils
import settings, utils, cfg, search, suggest, AboutDialog, processes

{.push callConv:cdecl.}

const
  NimrodProjectExt = ".nimprj"
  GTKVerReq = (2'i32, 12'i32, 0'i32) # Version of GTK required for Aporia to run.
  aporiaVersion = "0.1.2"
  helpText = """./aporia [args] filename...
  -v  --version  Reports aporia's version
  -h  --help Shows this message
"""

var win: utils.MainWin
win.Tabs = @[]

search.win = addr(win)
processes.win = addr(win)

var lastSession: seq[string] = @[]

var confParseFail = False # This gets set to true
                          # When there is an error parsing the config

proc writeHelp() =
  echo(helpText)
  quit(QuitSuccess)

proc writeVersion() =
  echo("Aporia v$1 compiled at $2 $3.\nCopyright (c) Dominik Picheta 2010-2012" % 
       [aporiaVersion, compileDate, compileTime])
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
try:
  win.settings = cfg.load(lastSession)
except ECFGParse:
  # TODO: Make the dialog show the exception
  confParseFail = True
  win.settings = cfg.defaultSettings()
except EIO:
  win.settings = cfg.defaultSettings()
    
proc getProjectTab(): int = 
  for i in 0..high(win.tabs): 
    if win.tabs[i].filename.endswith(NimrodProjectExt): return i

proc updateMainTitle(pageNum: int) =
  if win.Tabs.len()-1 >= pageNum:
    var name = ""
    if win.Tabs[pageNum].filename == "": name = "Untitled" 
    else: name = win.Tabs[pageNum].filename.extractFilename
    win.w.setTitle("Aporia - " & name)
  
proc saveTab(tabNr: int, startpath: string, updateGUI: bool = true) =
  if tabNr < 0: return
  if win.Tabs[tabNr].saved: return
  var path = ""
  if win.Tabs[tabNr].filename == "":
    path = ChooseFileToSave(win.w, startpath)
    if path != "":
      # Change syntax highlighting for this tab.
      var langMan = languageManagerGetDefault()
      var lang = langMan.guessLanguage(path, nil)
      if lang != nil:
        win.Tabs[tabNr].buffer.setLanguage(lang)
      else:
        win.Tabs[tabNr].buffer.setHighlightSyntax(False)
  else: 
    path = win.Tabs[tabNr].filename
  
  if path != "":
    var buffer = PTextBuffer(win.Tabs[tabNr].buffer)
    # Get the text from the TextView
    var startIter: TTextIter
    buffer.getStartIter(addr(startIter))
    
    var endIter: TTextIter
    buffer.getEndIter(addr(endIter))
    
    var text = buffer.getText(addr(startIter), addr(endIter), False)
    # Save it to a file
    var f: TFile
    if open(f, path, fmWrite):
      f.write(text)
      f.close()
      
      win.tempStuff.lastSaveDir = splitFile(path).dir
      
      # Change the tab name and .Tabs.filename etc.
      win.Tabs[tabNr].filename = path
      win.Tabs[tabNr].saved = True
      if updateGUI:
        var name = extractFilename(path)
        
        var cTab = win.Tabs[tabNr]
        cTab.label.setText(name)
        cTab.label.setTooltipText(path)
        
        updateMainTitle(tabNr)
    else:
      error(win.w, "Unable to write to file: " & OSErrorMsg())  

proc saveAllTabs() =
  for i in 0..high(win.tabs): 
    saveTab(i, os.splitFile(win.tabs[i].filename).dir)

# GTK Events
# -- w(PWindow)
proc destroy(widget: PWidget, data: pgpointer) {.cdecl.} =
  # gather some settings
  win.settings.VPanedPos = PPaned(win.sourceViewTabs.getParent()).getPosition()
  win.settings.winWidth = win.w.allocation.width
  win.settings.winHeight = win.w.allocation.height

  # save the settings
  win.save()
  # then quit
  main_quit()

proc confirmUnsaved(win: var MainWin, t: Tab): int =
  var askSave = dialogNewWithButtons("", win.w, 0,
                        STOCK_SAVE, RESPONSE_ACCEPT, STOCK_CANCEL, 
                        RESPONSE_CANCEL,
                        "Close without saving", RESPONSE_REJECT, nil)
  askSave.setTransientFor(win.w)
  # TODO: Make this dialog look better
  var labelText = ""
  if t.filename != "":
    labelText = t.filename.extractFilename & 
        " is unsaved, would you like to save it?"
  else:
    labelText = "Would you like to save this tab?"
  
  var label = labelNew(labelText)
  askSave.vbox.pack_start(label, False, False, 0)
  label.show()

  result = askSave.run()
  gtk2.destroy(PWidget(askSave))

proc delete_event(widget: PWidget, event: PEvent, user_data: pgpointer): bool =
  var quit = True
  for i in win.Tabs.low .. win.Tabs.len-1:
    if not win.Tabs[i].saved:
      # Only ask to save if file isn't empty
      if win.Tabs[i].buffer.get_char_count != 0:
        win.sourceViewTabs.setCurrentPage(i.int32)
        var resp = win.confirmUnsaved(win.tabs[i])
        if resp == RESPONSE_ACCEPT:
          saveTab(i, os.splitFile(win.tabs[i].filename).dir)
          quit = True
        elif resp == RESPONSE_CANCEL:
          quit = False
          break
        elif resp == RESPONSE_REJECT:
          quit = True
        else:
          quit = False
          break

  # If False is returned the window will close
  return not quit

proc windowState_Changed(widget: PWidget, event: PEventWindowState, 
                         user_data: pgpointer) =
  win.settings.winMaximized = (event.newWindowState and 
                               WINDOW_STATE_MAXIMIZED) != 0

proc window_configureEvent(widget: PWidget, event: PEventConfigure,
                           ud: pgpointer): gboolean =
  if win.suggest.shown:
    var current = win.SourceViewTabs.getCurrentPage()
    var tab     = win.Tabs[current]
    var start: TTextIter
    # Get the iter at the cursor position.
    tab.buffer.getIterAtMark(addr(start), tab.buffer.getInsert())
    moveSuggest(win, addr(start), tab)

  return False

proc cycleTab(win: var MainWin) =
  var current = win.SourceViewTabs.getCurrentPage()
  if current + 1 >= win.tabs.len():
    current = 0
  else:
    current.inc(1)
  
  # select next tab
  win.sourceViewTabs.setCurrentPage(current)

proc closeTab(tab: int) =
  var close = true
  if not win.tabs[tab].saved:
    # Only ask to save if file isn't empty
    if win.Tabs[tab].buffer.get_char_count != 0:
      var resp = win.confirmUnsaved(win.tabs[tab])
      if resp == RESPONSE_ACCEPT:
        saveTab(tab, os.splitFile(win.tabs[tab].filename).dir)
        close = True
      elif resp == RESPONSE_CANCEL:
        close = False
      elif resp == RESPONSE_REJECT:
        close = True
      else:
        close = False
  
  if close:
    system.delete(win.Tabs, tab)
    win.sourceViewTabs.removePage(int32(tab))

proc window_keyPress(widg: PWidget, event: PEventKey, 
                          userData: pgpointer): bool =
  # TODO: Make sure this doesn't interfere with normal key handling.
  result = false
  var modifiers = acceleratorGetDefaultModMask()

  if (event.state and modifiers) == CONTROL_MASK:
    # Ctrl pressed.
    case event.keyval
    of KeyF5:
      # Ctrl + Tab
      win.cycleTab()
      return true
    of KeyW:
      # Ctrl + W
      closeTab(win.SourceViewTabs.getCurrentPage())
      return True
    else: nil

  if event.keyval == KeyEscape:
    # Esc pressed
    win.findBar.hide()
    win.goLineBar.bar.hide()
    var current = win.SourceViewTabs.getCurrentPage()
    win.tabs[current].sourceView.grabFocus()
    

# -- SourceView(PSourceView) & SourceBuffer
proc updateStatusBar(buffer: PTextBuffer){.cdecl.} =
  # Incase this event gets fired before
  # bottomBar is initialized
  if win.bottomBar != nil and not win.tempStuff.stopSBUpdates:
    var iter: TTextIter
    
    win.bottomBar.pop(0)
    buffer.getIterAtMark(addr(iter), buffer.getInsert())

    var row = getLine(addr(iter)) + 1
    var col = getLineOffset(addr(iter))

    discard win.bottomBar.push(0, "Line: " & $row & " Column: " & $col)
  
proc cursorMoved(buffer: PTextBuffer, location: PTextIter, 
                 mark: PTextMark, user_data: pgpointer){.cdecl.} =
  updateStatusBar(buffer)

proc onCloseTab(btn: PButton, user_data: PWidget)
proc tab_buttonRelease(widg: PWidget, ev: PEventButton,
                       userDat: pwidget): bool
proc createTabLabel(name: string, t_child: PWidget): tuple[box: PWidget,
                    label: PLabel, closeBtn: PButton] =                  
  var eventBox = eventBoxNew()
  eventBox.setVisibleWindow(false)
  discard signal_connect(eventBox, "button-release-event",
                    SIGNAL_FUNC(tab_buttonRelease), t_child)
  
  var box = hboxNew(False, 0)
  var label = labelNew(name)
  var closebtn = buttonNew()
  closeBtn.setLabel(nil)
  var iconSize = iconSizeFromName("tabIconSize")
  if iconSize == 0:
     iconSize = iconSizeRegister("tabIconSize", 10, 10)
  var image = imageNewFromStock(STOCK_CLOSE, iconSize)
  discard gSignalConnect(closebtn, "clicked", G_Callback(onCloseTab), t_child)
  closebtn.setImage(image)
  gtk2.setRelief(closebtn, RELIEF_NONE)
  box.packStart(label, True, True, 0)
  box.packEnd(closebtn, False, False, 0)
  box.showAll()

  eventBox.add(box)
  return (eventBox, label, closeBtn)

proc onChanged(buffer: PTextBuffer, user_data: pgpointer) =
  ## This function is connected to the "changed" event on `buffer`.
  # Change the tabs state to 'unsaved'
  # and add '*' to the Tab Name
  var current = win.SourceViewTabs.getCurrentPage()
  var name = ""
  if win.Tabs[current].filename == "":
    win.Tabs[current].saved = False
    name = "Untitled *"
  else:
    win.Tabs[current].saved = False
    name = extractFilename(win.Tabs[current].filename) & " *"
  
  var cTab = win.Tabs[current]
  cTab.label.setText(name)

proc SourceViewKeyPress(sourceView: PWidget, event: PEventKey, 
                          userData: pgpointer): bool =
  result = false
  var key = $keyval_name(event.keyval)
  case key.toLower()
  of "up", "down", "page_up", "page_down":
    if win.settings.suggestFeature and win.suggest.shown:
      var selection = win.suggest.treeview.getSelection()
      var selectedIter: TTreeIter
      var TreeModel = win.suggest.TreeView.getModel()
      
      # Get current tab(For tooltip)
      var current = win.SourceViewTabs.getCurrentPage()
      var tab     = win.Tabs[current]
      
      template nextTimes(t: expr): stmt =
        for i in 0..t:
          next(selectedPath)
      template prevTimes(t: expr): stmt =
        for i in 0..t:
          moved = prev(selectedPath)
      
      if selection.getSelected(cast[PPGtkTreeModel](addr(TreeModel)),
                               addr(selectedIter)):
        var selectedPath = TreeModel.getPath(addr(selectedIter))

        var moved = False
        case key.toLower():
        of "up":
          moved = prev(selectedPath)
        of "down":
          moved = True
          next(selectedPath)
        of "page_up":
          prevTimes(5)
        of "page_down":
          moved = True
          nextTimes(5)
        
        if moved:
          # selectedPath is now the next or prev path.
          selection.selectPath(selectedPath)
          win.suggest.treeview.scroll_to_cell(selectedPath, nil, False, 0.5, 0.5)
          var index = selectedPath.getIndices()[]
          if win.suggest.items.len() > index:
            win.showTooltip(tab, win.suggest.items[index].nimType, selectedPath)
      else:
        # No item selected, select the first one.
        var selectedPath = tree_path_new_first()
        selection.selectPath(selectedPath)
        win.suggest.treeview.scroll_to_cell(selectedPath, nil, False, 0.5, 0.5)
        var index = selectedPath.getIndices()[]
        assert(index == 0)
        if win.suggest.items.len() > index:
          win.showTooltip(tab, win.suggest.items[index].nimType, selectedPath)
      
      # Return true to stop this event from moving the cursor down in the
      # source view.
      return True
  
  of "left", "right", "home", "end", "delete":
    if win.settings.suggestFeature and win.suggest.shown:
      win.suggest.hide()
  
  of "return", "space", "tab":
    if win.settings.suggestFeature and win.suggest.shown:
      echod("[Suggest] Selected.")
      var selection = win.suggest.treeview.getSelection()
      var selectedIter: TTreeIter
      var TreeModel = win.suggest.TreeView.getModel()
      if selection.getSelected(cast[PPGtkTreeModel](addr(TreeModel)),
                               addr(selectedIter)):
        var selectedPath = TreeModel.getPath(addr(selectedIter))
        var index = selectedPath.getIndices()[]
        win.insertSuggestItem(index)
        
        return True

  of "backspace":
    if win.settings.suggestFeature and win.suggest.shown:
      var current = win.SourceViewTabs.getCurrentPage()
      var tab     = win.Tabs[current]
      var endIter: TTextIter
      # Get the iter at the cursor position.
      tab.buffer.getIterAtMark(addr(endIter), tab.buffer.getInsert())
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
  else: nil

proc SourceViewKeyRelease(sourceView: PWidget, event: PEventKey, 
                          userData: pgpointer): bool =
  result = true
  var key = $keyval_name(event.keyval)
  case key.toLower()
  of "period":
    if win.settings.suggestFeature:
      if win.suggest.items.len() != 0: win.suggest.clear()
      doSuggest(win)

  of "backspace":
    if win.settings.suggestFeature and win.suggest.shown:
      # Don't need to know the char behind, because if it is a dot, then
      # the suggest dialog is hidden by ...KeyPress
      
      win.filterSuggest()
      win.doMoveSuggest()
  else:
    if key.toLower() notin ["up", "down", "page_up", "page_down", "home", "end"]:
      echod("Key released: ", key)

      if win.settings.suggestFeature and win.suggest.shown:
        win.filterSuggest()
        win.doMoveSuggest()

proc SourceViewMousePress(sourceView: PWidget, ev: PEvent, usr: gpointer): bool=
  win.suggest.hide()

# Other(Helper) functions

proc initSourceView(SourceView: var PSourceView, scrollWindow: var PScrolledWindow,
                    buffer: var PSourceBuffer) =
  # This gets called by addTab
  # Each tabs creates a new SourceView
  # SourceScrolledWindow(ScrolledWindow)
  scrollWindow = scrolledWindowNew(nil, nil)
  scrollWindow.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  scrollWindow.show()
  
  # SourceView(gtkSourceView)
  SourceView = sourceViewNew(buffer)
  SourceView.setInsertSpacesInsteadOfTabs(True)
  SourceView.setIndentWidth(win.settings.indentWidth)
  SourceView.setShowLineNumbers(win.settings.showLineNumbers)
  SourceView.setHighlightCurrentLine(
               win.settings.highlightCurrentLine)
  SourceView.setShowRightMargin(win.settings.rightMargin)
  SourceView.setAutoIndent(win.settings.autoIndent)
  discard signalConnect(SourceView, "button-press-event",
                        signalFunc(SourceViewMousePress), nil)

  var font = font_description_from_string(win.settings.font)
  SourceView.modifyFont(font)
  
  scrollWindow.add(SourceView)
  SourceView.show()

  buffer.setHighlightMatchingBrackets(
      win.settings.highlightMatchingBrackets)
  
  # UGLY workaround for yet another compiler bug:
  discard gsignalConnect(buffer, "mark-set", 
                         GCallback(aporia.cursorMoved), nil)
  discard gsignalConnect(buffer, "changed", GCallback(aporia.onChanged), nil)
  discard gsignalConnect(sourceView, "key-press-event", 
                         GCallback(SourceViewKeyPress), nil)
  discard gsignalConnect(sourceView, "key-release-event", 
                         GCallback(SourceViewKeyRelease), nil)

  # -- Set the syntax highlighter scheme
  buffer.setScheme(win.scheme)

proc findTab(filename: string, absolute: bool = true): int =
  for i in 0..win.Tabs.len()-1:
    if absolute:
      if win.Tabs[i].filename == filename: 
        return i
    else:
      if filename in win.Tabs[i].filename:
        return i 
      elif win.tabs[i].filename == "" and filename == ("a" & $i & ".nim"):
        return i

  return -1

proc addTab(name, filename: string, setCurrent: bool = False) =
  ## Adds a tab. If filename is not "", a file is read and set as the content
  ## of the new tab. If name is "" it will be either "Unknown" or the last part
  ## of the filename.
  ## If filename doesn't exist EIO is raised.
  assert(win.nimLang != nil)
  var buffer: PSourceBuffer = sourceBufferNew(win.nimLang)
  
  if filename != nil and filename != "":
    if setCurrent:
      # If a tab with the same filename already exists select it.
      var existingTab = findTab(filename)
      if existingTab != -1:
        # Select the existing tab
        win.sourceViewTabs.setCurrentPage(int32(existingTab))
        return
    
    # Guess the language of the file loaded
    var langMan = languageManagerGetDefault()
    var lang = langMan.guessLanguage(filename, nil)
    if lang != nil:
      buffer.setLanguage(lang)
    else:
      buffer.setHighlightSyntax(False)
  
  var nam = name
  if nam == "": nam = "Untitled"
  if filename == "": nam.add(" *")
  elif filename != "" and name == "":
    # Disable the undo/redo manager.
    buffer.begin_not_undoable_action()
    
    # Load the file.
    try:
      var file: string = readFile(filename)
      buffer.set_text(file, len(file).int32)
    except EIO:
      raise
    finally:
      # Enable the undo/redo manager.
      buffer.end_not_undoable_action()
      
    # Get the name.ext of the filename, for the tabs title
    nam = extractFilename(filename)
  
  # Init the sourceview
  var sourceView: PSourceView
  var scrollWindow: PScrolledWindow
  initSourceView(sourceView, scrollWindow, buffer)

  var (TabLabel, labelText, closeBtn) = createTabLabel(nam, scrollWindow)
  if filename != "": TabLabel.setTooltipText(filename)
  # Add a tab
  var nTab: Tab
  nTab.buffer = buffer
  nTab.sourceView = sourceView
  nTab.label = labelText
  nTab.saved = (filename != "")
  nTab.filename = filename
  nTab.closeBtn = closeBtn
  nTab.closeBtn.hide()
  win.Tabs.add(nTab)
  
  # Add the tab to the GtkNotebook
  let res = win.SourceViewTabs.appendPage(scrollWindow, TabLabel)
  assert res != -1
  win.SourceViewTabs.setTabReorderable(scrollWindow, true)

  PTextView(SourceView).setBuffer(nTab.buffer)

  if setCurrent:
    # Select the newly created tab
    win.sourceViewTabs.setCurrentPage(int32(win.Tabs.len())-1)

# GTK Events Contd.
# -- TopMenu & TopBar

proc recentFile_Activate(menuItem: PMenuItem, file: ptr string)
proc fileMenuItem_Activate(menu: PMenuItem, user_data: pgpointer) =
  if win.tempStuff.recentFileMenuItems.len > 0:
    for i in win.tempStuff.recentFileMenuItems:
      PWidget(i).destroy()

  win.tempStuff.recentFileMenuItems = @[]

  # Recently opened files
  # -- Show first ten in the File menu
  if win.settings.recentlyOpenedFiles.len > 0:
    let recent = win.settings.recentlyOpenedFiles
  
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
        win.FileMenu.append(recentFileMI)
      show(recentFileMI)
      
      discard signal_connect(recentFileMI, "activate", 
                             SIGNAL_FUNC(recentFile_Activate),
                             addr(win.settings.recentlyOpenedFiles[i]))
      addedItems.inc()
    
    if recent.len > 10:
      win.FileMenu.append(moreMenuItem)
      win.tempStuff.recentFileMenuItems.add(moreMenuItem)


proc newFile(menuItem: PMenuItem, user_data: pgpointer) = addTab("", "", True)
  
proc openFile(menuItem: PMenuItem, user_data: pgpointer) =
  var startpath = ""
  var currPage = win.SourceViewTabs.getCurrentPage()
  if currPage <% win.tabs.len: 
    startpath = os.splitFile(win.tabs[currPage].filename).dir

  if startpath.len == 0:
    # Use lastSavePath as the startpath
    startpath = win.tempStuff.lastSaveDir
    if isNil(startpath) or startpath.len == 0:
      startpath = os.getHomeDir()

  var files = ChooseFilesToOpen(win.w, startpath)
  if files.len() > 0:
    for f in items(files):
      try:
        addTab("", f, True)
        # Add to recently opened files.
        # TODO: Save settings?
        win.settings.recentlyOpenedFiles.add(f)
      except EIO:
        error(win.w, "Unable to read from file: " & getCurrentExceptionMsg())
  
proc saveFile_Activate(menuItem: PMenuItem, user_data: pgpointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  var startpath = os.splitFile(win.tabs[current].filename).dir
  if startpath == "":
    startpath = win.tempStuff.lastSaveDir
  
  saveTab(current, startpath)

proc saveFileAs_Activate(menuItem: PMenuItem, user_data: pgpointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  var (filename, saved) = (win.Tabs[current].filename, win.Tabs[current].saved)
  var startpath = os.splitFile(win.tabs[current].filename).dir
  if startpath == "":
    startpath = win.tempStuff.lastSaveDir

  win.Tabs[current].saved = False
  win.Tabs[current].filename = ""
  # saveTab will ask the user for a filename if the tabs filename is "".
  saveTab(current, startpath)
  # If the user cancels the save file dialog. Restore the previous filename
  # and saved state
  if win.Tabs[current].filename == "":
    win.Tabs[current].filename = filename
    win.Tabs[current].saved = saved

  updateMainTitle(current)

proc recentFile_Activate(menuItem: PMenuItem, file: ptr string) =
  let filename = file[]
  try:
    addTab("", filename, True)
  except EIO:
    error(win.w, "Unable to read from file: " & getCurrentExceptionMsg())

proc undo(menuItem: PMenuItem, user_data: pgpointer) = 
  var current = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[current].buffer.canUndo():
    win.Tabs[current].buffer.undo()
  win.scrollToInsert()
  
proc redo(menuItem: PMenuItem, user_data: pgpointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[current].buffer.canRedo():
    win.Tabs[current].buffer.redo()
  win.scrollToInsert()

proc setFindField() =
  # Get the selected text, and set the findEntry to it.
  var currentTab = win.SourceViewTabs.getCurrentPage()
  var insertIter: TTextIter
  win.Tabs[currentTab].buffer.getIterAtMark(addr(insertIter), 
                                      win.Tabs[currentTab].buffer.getInsert())
  var insertOffset = getOffset(addr insertIter)
  
  var selectIter: TTextIter
  win.Tabs[currentTab].buffer.getIterAtMark(addr(selectIter), 
                win.Tabs[currentTab].buffer.getSelectionBound())
  var selectOffset = getOffset(addr selectIter)
  
  if insertOffset != selectOffset:
    var text = win.Tabs[currentTab].buffer.getText(addr(insertIter), 
                                                   addr(selectIter), false)
    win.findEntry.setText(text)

proc find_Activate(menuItem: PMenuItem, user_data: pgpointer) = 
  setFindField()

  win.findBar.show()
  win.findEntry.grabFocus()
  win.replaceEntry.hide()
  win.replaceLabel.hide()
  win.replaceBtn.hide()
  win.replaceAllBtn.hide()

proc replace_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  setFindField()

  win.findBar.show()
  win.findEntry.grabFocus()
  win.replaceEntry.show()
  win.replaceLabel.show()
  win.replaceBtn.show()
  win.replaceAllBtn.show()
  
proc GoLine_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  win.goLineBar.bar.show()
  win.goLineBar.entry.grabFocus()
  
proc settings_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  settings.showSettings(win)

proc viewToolBar_Toggled(menuitem: PCheckMenuItem, user_data: pgpointer) =
  win.settings.toolBarVisible = menuitem.itemGetActive()
  if win.settings.toolBarVisible:
    win.toolBar.show()
  else:
    win.toolBar.hide()

proc viewBottomPanel_Toggled(menuitem: PCheckMenuItem, user_data: pgpointer) =
  win.settings.bottomPanelVisible = menuitem.itemGetActive()
  if win.settings.bottomPanelVisible:
    win.bottomPanelTabs.show()
  else:
    win.bottomPanelTabs.hide()

proc GetCmd(cmd, filename: string): string = 
  var f = quoteIfContainsWhite(filename)
  if cmd =~ peg"\s* '$' y'findExe' '(' {[^)]+} ')' {.*}":
    var exe = quoteIfContainsWhite(findExe(matches[0]))
    if exe.len == 0: exe = matches[0]
    result = exe & " " & matches[1] % f
  else:
    result = cmd % f

proc showBottomPanel() =
  if not win.settings.bottomPanelVisible:
    win.bottomPanelTabs.show()
    win.settings.bottomPanelVisible = true
    PCheckMenuItem(win.viewBottomPanelMenuItem).itemSetActive(true)

proc saveForCompile(currentTab: int): string =
  if win.Tabs[currentTab].filename.len == 0:
    # Save to /tmp
    if not existsDir(getTempDir() / "aporia"): createDir(getTempDir() / "aporia")
    result = getTempDir() / "aporia" / "a" & ($currentTab).addFileExt("nim")
    win.Tabs[currentTab].filename = result
    saveTab(currentTab, os.splitFile(win.tabs[currentTab].filename).dir, false)
    win.Tabs[currentTab].filename = ""
    win.Tabs[currentTab].saved = false
  else:
    saveTab(currentTab, os.splitFile(win.tabs[currentTab].filename).dir)
    result = win.tabs[currentTab].filename

proc saveAllForCompile(projectTab: int): string =
  for i, tab in win.tabs:
    if i == projectTab:
      result = saveForCompile(i)
    else:
      discard saveForCompile(i)

proc compileRun(filename: string, shouldRun: bool) =
  if filename.len == 0: return
  if win.tempStuff.execMode != ExecNone:
    win.w.error("Process already running!")
    return
  
  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()

  var cmd = GetCmd(win.settings.nimrodCmd, filename)
  # Execute the compiled application if compiled successfully.
  # ifSuccess is the filename of the compiled app.
  var ifSuccess = ""
  if shouldRun:
    ifSuccess = changeFileExt(filename, os.ExeExt)
  execProcAsync(cmd, ExecNimrod, ifSuccess)

proc CompileCurrent_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  let filename = saveForCompile(win.SourceViewTabs.getCurrentPage())
  compileRun(filename, false)
  
proc CompileRunCurrent_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  let filename = saveForCompile(win.SourceViewTabs.getCurrentPage())
  compileRun(filename, true)

proc CompileProject_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  let filename = saveAllForCompile(getProjectTab())
  compileRun(filename, false)
  
proc CompileRunProject_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  let filename = saveAllForCompile(getProjectTab())
  compileRun(filename, true)

proc StopProcess_Activate(menuitem: PMenuItem, user_data: pgpointer) =

  if win.tempStuff.execMode != ExecNone and 
     win.tempStuff.execProcess != nil:
    echod("Terminating process... ID: ", $win.tempStuff.idleFuncId)
    win.tempStuff.execProcess.terminate()
    win.tempStuff.execProcess.close()
    #assert gSourceRemove(win.tempStuff.idleFuncId)
    # execMode is set to ExecNone in the idle proc. It must be this way.
    # Because otherwise EvStopped stays in the channel.
    
    var errorTag = createColor(win.outputTextView, "errorTag", "red")
    win.outputTextView.addText("> Process terminated\n", errorTag)
  else:
    echod("No process running.")

proc RunCustomCommand(cmd: string) = 
  if win.tempStuff.execMode != ExecNone:
    win.w.error("Process already running!")
    return
  
  saveFile_Activate(nil, nil)
  var currentTab = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[currentTab].filename.len == 0 or cmd.len == 0: return
  
  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()
  
  execProcAsync(GetCmd(cmd, win.Tabs[currentTab].filename), ExecCustom)

proc RunCustomCommand1(menuitem: PMenuItem, user_data: pgpointer) =
  RunCustomCommand(win.settings.customCmd1)

proc RunCustomCommand2(menuitem: PMenuItem, user_data: pgpointer) =
  RunCustomCommand(win.settings.customCmd2)

proc RunCustomCommand3(menuitem: PMenuItem, user_data: pgpointer) =
  RunCustomCommand(win.settings.customCmd3)

proc RunCheck(menuItem: PMenuItem, user_data: pgpointer) =
  let filename = saveForCompile(win.SourceViewTabs.getCurrentPage())
  if filename.len == 0: return
  if win.tempStuff.execMode != ExecNone:
    win.w.error("Process already running!")
    return
  
  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()

  var cmd = GetCmd("$findExe(nimrod) check $#", filename)
  execProcAsync(cmd, ExecNimrod)

proc memUsage_click(menuitem: PMenuItem, user_data: pgpointer) =
  echo("Memory usage: ")
  gMemProfile()
  var stats = "Memory usage: "
  stats.add gcGetStatistics()
  win.w.info(stats)

proc about_click(menuitem: PMenuItem, user_data: pgpointer) =
  # About dialog
  var aboutDialog = newAboutDialog("Aporia " & aporiaVersion, 
      "Aporia is an IDE for the \nNimrod programming language.",
      "Copyright (c) 2010-2012 Dominik Picheta")
  aboutDialog.show()

# -- SourceViewTabs - Notebook.

proc closeTab(child: PWidget) =
  var tab = win.sourceViewTabs.pageNum(child)
  closeTab(tab)

proc onCloseTab(btn: PButton, user_data: PWidget) =
  if win.sourceViewTabs.getNPages() > 1:
    closeTab(user_data)

proc tab_buttonRelease(widg: PWidget, ev: PEventButton,
                       userDat: pwidget): bool =
  if ev.button == 2: # Middle click.
    closeTab(userDat)

proc onTabsPressed(widg: PWidget, ev: PEventButton,
                       userDat: pwidget):bool =
  if ev.button == 1 and ev.`type` == BUTTON2_PRESS:
    addTab("", "", true)

proc onSwitchTab(notebook: PNotebook, page: PNotebookPage, pageNum: guint, 
                 user_data: pgpointer) =
  # hide close button of last active tab
  if win.tempStuff.lastTab < win.Tabs.len:
    win.Tabs[win.tempStuff.lastTab].closeBtn.hide()
  
  win.tempStuff.lastTab = pageNum
  updateMainTitle(pageNum)
  
  # Set the lastSavedDir
  if win.tabs.len > pageNum:
    if win.Tabs[pageNum].filename.len != 0:
      win.tempStuff.lastSaveDir = splitFile(win.Tabs[pageNum].filename).dir
  
  # Hide the suggest dialog
  win.suggest.hide()
  
  # Show close button of tab
  win.Tabs[pageNum].closeBtn.show()

proc onDragDataReceived(widget: PWidget, context: PDragContext, 
                        x: gint, y: gint, data: PSelectionData, info: guint,
                        time: guint, userData: pointer) =
  echod "dragDataReceived: ", $widget.getName()
  var success = False
  if data != nil and data.length >= 0:
    if info == 0:
      var sdata = cast[cstring](data.data)
      for line in `$`(sdata).splitLines():
        if line != "" and line.startswith("file://"):
          var path = line[7 .. -1]
          echod(path)
          var existingTab = findTab(path)
          if existingTab != -1:
            win.sourceViewTabs.setCurrentPage(int32(existingTab))
          else:
            addTab("", path, True)
      success = True
    else: echod("dragDataReceived: Unknown `info`")

  dragFinish(context, success, False, time)

proc onPageReordered(notebook: PNotebook, child: PWidget, pageNum: cuint, 
                     userData: pointer) =
  let oldPos = win.Tabs[win.tempStuff.lastTab]
  win.Tabs.delete(win.tempStuff.lastTab)
  win.Tabs.insert(oldPos, int(pageNum))
  
  win.tempStuff.lastTab = int(pageNum)

# -- Bottom tabs

proc errorList_RowActivated(tv: PTreeView, path: PTreePath, 
            column: PTreeViewColumn, d: pointer) =
  let selectedIndex = path.getIndices()[]
  let item = win.tempStuff.errorList[selectedIndex]
  var existingTab = findTab(item.file, false)
  if existingTab == -1:
    win.w.error("Could not find correct tab.")
  else:
    win.sourceViewTabs.setCurrentPage(int32(existingTab))
    
    # Move cursor to where the error is.
    var iter: TTextIter
    var iterPlus1: TTextIter 
    win.Tabs[existingTab].buffer.getIterAtLineOffset(addr(iter),
        int32(item.line.parseInt)-1, int32(item.column.parseInt))
    win.Tabs[existingTab].buffer.getIterAtLineOffset(addr(iterPlus1),
        int32(item.line.parseInt)-1, int32(item.column.parseInt)+1)
    
    win.Tabs[existingTab].buffer.moveMarkByName("insert", addr(iter))
    win.Tabs[existingTab].buffer.moveMarkByName("selection_bound",
        addr(iterPlus1))
    
    # TODO: This should be getting focus, but as usual it's not... FIXME
    win.Tabs[existingTab].sourceView.grabFocus()

    win.scrollToInsert(int32(existingTab))

# -- FindBar

proc nextBtn_Clicked(button: PButton, user_data: pgpointer) = findText(True)
proc prevBtn_Clicked(button: PButton, user_data: pgpointer) = findText(False)

proc replaceBtn_Clicked(button: PButton, user_data: pgpointer) =
  var currentTab = win.SourceViewTabs.getCurrentPage()
  var start, theEnd: TTextIter
  if not win.Tabs[currentTab].buffer.getSelectionBounds(
        addr(start), addr(theEnd)):
    # If no text is selected, try finding a match.
    findText(True)
    if not win.Tabs[currentTab].buffer.getSelectionBounds(
          addr(start), addr(theEnd)):
      # No match
      return

  win.Tabs[currentTab].buffer.beginUserAction()
  # Remove the text
  gtk2.delete(win.Tabs[currentTab].buffer, addr(start), addr(theEnd))
  # Insert the replacement
  var text = getText(win.replaceEntry)
  win.Tabs[currentTab].buffer.insert(addr(start), text, int32(len(text)))

  win.Tabs[currentTab].buffer.endUserAction()
  
  # Find next match, this is just a convenience.
  findText(True)
  
proc replaceAllBtn_Clicked(button: PButton, user_data: pgpointer) =
  var find = getText(win.findEntry)
  var replace = getText(win.replaceEntry)
  var count = replaceAll(find, replace)
  echo("Replaced $1 matches." % $count)
  
proc closeBtn_Clicked(button: PButton, user_data: pgpointer) = 
  win.findBar.hide()

proc caseSens_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer) =
  win.settings.search = SearchCaseSens
proc caseInSens_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer) =
  win.settings.search = SearchCaseInsens
proc style_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer) =
  win.settings.search = SearchStyleInsens
proc regex_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer) =
  win.settings.search = SearchRegex
proc peg_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer) =
  win.settings.search = SearchPeg

proc extraBtn_Clicked(button: PButton, user_data: pgpointer) =
  var extraMenu = menuNew()
  var group: PGSList

  var caseSensMenuItem = radio_menu_item_new(group, "Case sensitive")
  extraMenu.append(caseSensMenuItem)
  discard signal_connect(caseSensMenuItem, "toggled", 
                          SIGNAL_FUNC(caseSens_Changed), nil)
  caseSensMenuItem.show()
  group = caseSensMenuItem.ItemGetGroup()
  
  var caseInSensMenuItem = radio_menu_item_new(group, "Case insensitive")
  extraMenu.append(caseInSensMenuItem)
  discard signal_connect(caseInSensMenuItem, "toggled", 
                          SIGNAL_FUNC(caseInSens_Changed), nil)
  caseInSensMenuItem.show()
  group = caseInSensMenuItem.ItemGetGroup()
  
  var styleMenuItem = radio_menu_item_new(group, "Style insensitive")
  extraMenu.append(styleMenuItem)
  discard signal_connect(styleMenuItem, "toggled", 
                          SIGNAL_FUNC(style_Changed), nil)
  styleMenuItem.show()
  group = styleMenuItem.ItemGetGroup()
  
  var regexMenuItem = radio_menu_item_new(group, "Regex")
  extraMenu.append(regexMenuItem)
  discard signal_connect(regexMenuItem, "toggled", 
                          SIGNAL_FUNC(regex_Changed), nil)
  regexMenuItem.show()
  group = regexMenuItem.ItemGetGroup()
  
  var pegMenuItem = radio_menu_item_new(group, "Pegs")
  extraMenu.append(pegMenuItem)
  discard signal_connect(pegMenuItem, "toggled", 
                          SIGNAL_FUNC(peg_Changed), nil)
  pegMenuItem.show()
  
  # Make the correct radio button active
  case win.settings.search
  of SearchCaseSens:
    PCheckMenuItem(caseSensMenuItem).ItemSetActive(True)
  of SearchCaseInsens:
    PCheckMenuItem(caseInSensMenuItem).ItemSetActive(True)
  of SearchStyleInsens:
    PCheckMenuItem(styleMenuItem).ItemSetActive(True)
  of SearchRegex:
    PCheckMenuItem(regexMenuItem).ItemSetActive(True)
  of SearchPeg:
    PCheckMenuItem(pegMenuItem).ItemSetActive(True)

  extraMenu.popup(nil, nil, nil, nil, 0, get_current_event_time())

# Go to line bar.
proc goLine_Changed(ed: PEditable, d: pgpointer) =
  var line = win.goLineBar.entry.getText()
  var lineNum: biggestInt = -1
  if parseBiggestInt($line, lineNum) != 0:
    # Get current tab
    var current = win.SourceViewTabs.getCurrentPage()
    template buffer: expr = win.tabs[current].buffer
    if not (lineNum-1 < 0 or (lineNum > buffer.getLineCount())):
      var iter: TTextIter
      buffer.getIterAtLine(addr(iter), int32(lineNum)-1)
      
      buffer.moveMarkByName("insert", addr(iter))
      buffer.moveMarkByName("selection_bound", addr(iter))
      discard PTextView(win.Tabs[current].sourceView).
          scrollToIter(addr(iter), 0.2, False, 0.0, 0.0)
      
      # Reset entry color.
      win.goLineBar.entry.modifyBase(STATE_NORMAL, nil)
      win.goLineBar.entry.modifyText(STATE_NORMAL, nil)
      return # Success
  
  # Make entry red.
  var red: Gdk2.TColor
  discard colorParse("#ff6666", addr(red))
  var white: Gdk2.TColor
  discard colorParse("white", addr(white))
  
  win.goLineBar.entry.modifyBase(STATE_NORMAL, addr(red))
  win.goLineBar.entry.modifyText(STATE_NORMAL, addr(white))

proc goLineClose_clicked(button: PButton, user_data: pgpointer) = 
  win.goLineBar.bar.hide()

# GUI Initialization


proc createAccelMenuItem(toolsMenu: PMenu, accGroup: PAccelGroup, 
                         label: string, acc: gint,
                         action: proc (i: PMenuItem, p: pgpointer),
                         mask: gint = 0) = 
  var result = menu_item_new(label)
  result.addAccelerator("activate", accGroup, acc, mask, ACCEL_VISIBLE)
  ToolsMenu.append(result)
  show(result)
  discard signal_connect(result, "activate", SIGNAL_FUNC(action), nil)

proc createSeparator(menu: PMenu) =
  var sep = separator_menu_item_new()
  menu.append(sep)
  sep.show()

proc initTopMenu(MainBox: PBox) =
  # Create a accelerator group, used for shortcuts
  # like CTRL + S in SaveMenuItem
  var accGroup = accel_group_new()
  add_accel_group(win.w, accGroup)

  # TopMenu(MenuBar)
  var TopMenu = menuBarNew()
  
  # FileMenu
  win.FileMenu = menuNew()

  var NewMenuItem = menu_item_new("New") # New
  NewMenuItem.add_accelerator("activate", accGroup, 
                  KEY_n, CONTROL_MASK, ACCEL_VISIBLE)
  win.FileMenu.append(NewMenuItem)
  show(NewMenuItem)
  discard signal_connect(NewMenuItem, "activate", 
                          SIGNAL_FUNC(newFile), nil)

  createSeparator(win.FileMenu)

  var OpenMenuItem = menu_item_new("Open...") # Open...
  # CTRL + O
  OpenMenuItem.add_accelerator("activate", accGroup, 
                  KEY_o, CONTROL_MASK, ACCEL_VISIBLE) 
  win.FileMenu.append(OpenMenuItem)
  show(OpenMenuItem)
  discard signal_connect(OpenMenuItem, "activate", 
                          SIGNAL_FUNC(aporia.openFile), nil)
  
  var SaveMenuItem = menu_item_new("Save") # Save
  # CTRL + S
  SaveMenuItem.add_accelerator("activate", accGroup, 
                  KEY_s, CONTROL_MASK, ACCEL_VISIBLE) 
  win.FileMenu.append(SaveMenuItem)
  show(SaveMenuItem)
  discard signal_connect(SaveMenuItem, "activate", 
                          SIGNAL_FUNC(saveFile_activate), nil)

  var SaveAsMenuItem = menu_item_new("Save As...") # Save as...

  SaveAsMenuItem.add_accelerator("activate", accGroup, 
                  KEY_s, CONTROL_MASK or gdk2.SHIFT_MASK, ACCEL_VISIBLE) 
  win.FileMenu.append(SaveAsMenuItem)
  show(SaveAsMenuItem)
  discard signal_connect(SaveAsMenuItem, "activate", 
                          SIGNAL_FUNC(saveFileAs_Activate), nil)
  
  createSeparator(win.FileMenu)
  
  var FileMenuItem = menuItemNewWithMnemonic("_File")
  discard signalConnect(FileMenuItem, "activate",
                        SIGNAL_FUNC(fileMenuItem_Activate), nil)

  FileMenuItem.setSubMenu(win.FileMenu)
  FileMenuItem.show()
  TopMenu.append(FileMenuItem)
  
  # Edit menu
  var EditMenu = menuNew()

  var UndoMenuItem = menu_item_new("Undo") # Undo
  EditMenu.append(UndoMenuItem)
  show(UndoMenuItem)
  discard signal_connect(UndoMenuItem, "activate", 
                          SIGNAL_FUNC(aporia.undo), nil)
  
  var RedoMenuItem = menu_item_new("Redo") # Undo
  EditMenu.append(RedoMenuItem)
  show(RedoMenuItem)
  discard signal_connect(RedoMenuItem, "activate", 
                          SIGNAL_FUNC(aporia.redo), nil)

  createSeparator(EditMenu)
  
  var FindMenuItem = menu_item_new("Find") # Find
  FindMenuItem.add_accelerator("activate", accGroup, 
                  KEY_f, CONTROL_MASK, ACCEL_VISIBLE) 
  EditMenu.append(FindMenuItem)
  show(FindMenuItem)
  discard signal_connect(FindMenuItem, "activate", 
                          SIGNAL_FUNC(aporia.find_Activate), nil)

  var ReplaceMenuItem = menu_item_new("Replace") # Replace
  ReplaceMenuItem.add_accelerator("activate", accGroup, 
                  KEY_h, CONTROL_MASK, ACCEL_VISIBLE) 
  EditMenu.append(ReplaceMenuItem)
  show(ReplaceMenuItem)
  discard signal_connect(ReplaceMenuItem, "activate", 
                          SIGNAL_FUNC(aporia.replace_Activate), nil)

  createSeparator(EditMenu)
  
  var GoLineMenuItem = menu_item_new("Go to line...") # Go to line
  GoLineMenuItem.add_accelerator("activate", accGroup, 
                  KEY_l, CONTROL_MASK, ACCEL_VISIBLE) 
  EditMenu.append(GoLineMenuItem)
  show(GoLineMenuItem)
  discard signal_connect(GoLineMenuItem, "activate", 
                          SIGNAL_FUNC(GoLine_Activate), nil)
  
  createSeparator(EditMenu)
  
  var SettingsMenuItem = menu_item_new("Settings...") # Settings
  EditMenu.append(SettingsMenuItem)
  show(SettingsMenuItem)
  discard signal_connect(SettingsMenuItem, "activate", 
                          SIGNAL_FUNC(aporia.Settings_Activate), nil)

  var EditMenuItem = menuItemNewWithMnemonic("_Edit")

  EditMenuItem.setSubMenu(EditMenu)
  EditMenuItem.show()
  TopMenu.append(EditMenuItem)
  
  # View menu
  var ViewMenu = menuNew()
  
  win.viewToolBarMenuItem = check_menu_item_new("Tool Bar")
  PCheckMenuItem(win.viewToolBarMenuItem).itemSetActive(
         win.settings.toolBarVisible)
  ViewMenu.append(win.viewToolBarMenuItem)
  show(win.viewToolBarMenuItem)
  discard signal_connect(win.viewToolBarMenuItem, "toggled", 
                          SIGNAL_FUNC(aporia.viewToolBar_Toggled), nil)
  
  win.viewBottomPanelMenuItem = check_menu_item_new("Bottom Panel")
  PCheckMenuItem(win.viewBottomPanelMenuItem).itemSetActive(
         win.settings.bottomPanelVisible)
  win.viewBottomPanelMenuItem.add_accelerator("activate", accGroup, 
                  KEY_b, CONTROL_MASK or SHIFT_MASK, ACCEL_VISIBLE) 
  ViewMenu.append(win.viewBottomPanelMenuItem)
  show(win.viewBottomPanelMenuItem)
  discard signal_connect(win.viewBottomPanelMenuItem, "toggled", 
                          SIGNAL_FUNC(aporia.viewBottomPanel_Toggled), nil)
  
  var ViewMenuItem = menuItemNewWithMnemonic("_View")

  ViewMenuItem.setSubMenu(ViewMenu)
  ViewMenuItem.show()
  TopMenu.append(ViewMenuItem)       
  
  
  # Tools menu
  var ToolsMenu = menuNew()

  createAccelMenuItem(ToolsMenu, accGroup, "Compile current file", 
                      KEY_F4, aporia.CompileCurrent_Activate)
  createAccelMenuItem(ToolsMenu, accGroup, "Compile & run current file", 
                      KEY_F5, aporia.CompileRunCurrent_Activate)
  createSeparator(ToolsMenu)
  createAccelMenuItem(ToolsMenu, accGroup, "Compile project", 
                      KEY_F8, aporia.CompileProject_Activate)
  createAccelMenuItem(ToolsMenu, accGroup, "Compile & run project", 
                      KEY_F9, aporia.CompileRunProject_Activate)
  createAccelMenuItem(ToolsMenu, accGroup, "Terminate running process", 
                      KEY_F7, aporia.StopProcess_Activate)
  createSeparator(ToolsMenu)
  createAccelMenuItem(ToolsMenu, accGroup, "Run custom command 1", 
                      KEY_F1, aporia.RunCustomCommand1)
  createAccelMenuItem(ToolsMenu, accGroup, "Run custom command 2", 
                      KEY_F2, aporia.RunCustomCommand2)
  createAccelMenuItem(ToolsMenu, accGroup, "Run custom command 3", 
                      KEY_F3, aporia.RunCustomCommand3)
  createSeparator(ToolsMenu)
  createAccelMenuItem(ToolsMenu, accGroup, "Check", 
                      KEY_F5, aporia.RunCheck, CONTROL_MASK)
  
  
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
  
  var AboutMenuItem = menu_item_new("About")
  HelpMenu.append(AboutMenuItem)
  show(AboutMenuItem)
  discard signal_connect(AboutMenuItem, "activate", 
                         SIGNAL_FUNC(aporia.About_click), nil)
  
  var HelpMenuItem = menuItemNewWithMnemonic("_Help")
  
  HelpMenuItem.setSubMenu(HelpMenu)
  HelpMenuItem.show()
  TopMenu.append(HelpMenuItem)
  
  MainBox.packStart(TopMenu, False, False, 0)
  TopMenu.show()

proc initToolBar(MainBox: PBox) =
  # Create top ToolBar
  win.toolBar = toolbarNew()
  win.toolBar.setStyle(TOOLBAR_ICONS)
  
  var NewFileItem = win.toolBar.insertStock(STOCK_NEW, "New File",
                      "New File", SIGNAL_FUNC(aporia.newFile), nil, 0)
  win.toolBar.appendSpace()
  var OpenItem = win.toolBar.insertStock(STOCK_OPEN, "Open",
                      "Open", SIGNAL_FUNC(aporia.openFile), nil, -1)
  var SaveItem = win.toolBar.insertStock(STOCK_SAVE, "Save",
                      "Save", SIGNAL_FUNC(saveFile_Activate), nil, -1)
  win.toolBar.appendSpace()
  var UndoItem = win.toolBar.insertStock(STOCK_UNDO, "Undo", 
                      "Undo", SIGNAL_FUNC(aporia.undo), nil, -1)
  var RedoItem = win.toolBar.insertStock(STOCK_REDO, "Redo",
                      "Redo", SIGNAL_FUNC(aporia.redo), nil, -1)
  
  MainBox.packStart(win.toolBar, False, False, 0)
  if win.settings.toolBarVisible == true:
    win.toolBar.show()

proc createTargetEntry(target: string, flags, info: int): TTargetEntry =
  result.target = target
  result.flags = flags.int32
  result.info = info.int32

proc initSourceViewTabs() =
  win.SourceViewTabs = notebookNew()
  discard win.SourceViewTabs.signalConnect(
          "switch-page", SIGNAL_FUNC(onSwitchTab), nil)
  win.SourceViewTabs.set_scrollable(True)
  
  # Drag and Drop setup
  # TODO: This should only allow files.
  var targetList = createTargetEntry("STRING", 0, 0)
  
  win.SourceViewTabs.dragDestSet(DEST_DEFAULT_ALL, addr(targetList),
                                 1, ACTION_COPY)
  discard win.SourceViewTabs.signalConnect(
          "drag-data-received", SIGNAL_FUNC(onDragDataReceived), nil)
  
  discard win.sourceViewTabs.signalConnect("page-reordered",
          SIGNAL_FUNC(onPageReordered), nil)
  
  # TODO: only create new tab when double-clicking in empty space
  discard win.SourceViewTabs.signalConnect("button-press-event",
          SIGNAL_FUNC(onTabsPressed), nil)
  
  win.SourceViewTabs.show()
  if lastSession.len != 0 or loadFiles.len != 0:
    var count = 0
    for i in 0 .. lastSession.len-1:
      var splitUp = lastSession[i].split('|')
      var (filename, offset) = (splitUp[0], splitUp[1])
      if existsFile(filename):
        addTab("", filename)
      
        var iter: TTextIter
        # TODO: Save last cursor position as line and column offset combo.
        # This will help with int overflows which would happen more often with
        # a char offset.
        win.Tabs[count].buffer.getIterAtOffset(addr(iter), int32(offset.parseInt()))
        win.Tabs[count].buffer.placeCursor(addr(iter))
        
        var mark = win.Tabs[count].buffer.getInsert()
        
        # This only seems to work with those last 3 params.
        # TODO: Get it to center. Inspect gedit's source code to see how it does
        # this.
        win.Tabs[count].sourceView.scrollToMark(mark, 0.0, False, 0.0, 0.0)
        #win.Tabs[count].sourceView.scroll_mark_onscreen(mark)
        #win.Tabs[i].sourceView.scrollToMark(mark, 0.25, true, 0.0, 0.5)
        #win.Tabs[i].sourceView.scrollMarkOnscreen(mark)
        inc(count)
      else: dialogs.error(win.w, "Could not restore file from session, file not found: " & filename)
    
    for f in loadFiles:
      if existsFile(f):
        addTab("", f)
      else:
        dialogs.error(win.w, "Could not open " & f)
        quit(QuitFailure)
    
    if loadFiles.len() != 0:
      # Select the tab that was opened.
      win.sourceViewTabs.setCurrentPage(int32(win.tabs.len())-1)
    
  else:
    addTab("", "")

proc initBottomTabs() =
  win.bottomPanelTabs = notebookNew()
  if win.settings.bottomPanelVisible:
    win.bottomPanelTabs.show()
  
  # -- output tab
  var tabLabel = labelNew("Output")
  var outputTab = vboxNew(False, 0)
  discard win.bottomPanelTabs.appendPage(outputTab, tabLabel)
  # Compiler tabs, gtktextview
  var outputScrolledWindow = scrolledwindowNew(nil, nil)
  outputScrolledWindow.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  outputTab.packStart(outputScrolledWindow, true, true, 0)
  outputScrolledWindow.show()
  
  win.outputTextView = textviewNew()
  outputScrolledWindow.add(win.outputTextView)
  win.outputTextView.show()
  # Create a mark at the end of the outputTextView.
  var endIter: TTextIter
  win.outputTextView.getBuffer().getEndIter(addr(endIter))
  discard win.outputTextView.
          getBuffer().createMark("endMark", addr(endIter), False)
  
  outputTab.show()

  # -- errors tab
  var errorListLabel = labelNew("Error list")
  var errorListTab = vboxNew(false, 0)
  discard win.bottomPanelTabs.appendPage(errorListTab, errorListLabel)
  
  var errorsScrollWin = scrolledWindowNew(nil, nil)
  errorsScrollWin.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  errorListTab.packStart(errorsScrollWin, True, True, 0)
  errorsScrollWin.show()
  
  win.errorListWidget = treeviewNew()
  discard win.errorListWidget.signalConnect("row-activated",
              SIGNAL_FUNC(errorList_RowActivated), nil)
  
  errorsScrollWin.add(win.errorListWidget)
  
  win.errorListWidget.createTextColumn("Type", 0)
  win.errorListWidget.createTextColumn("Description", 1, true)
  win.errorListWidget.createTextColumn("File", 2)
  win.errorListWidget.createTextColumn("Line", 3)
  win.errorListWidget.createTextColumn("Column", 4)

  # There are 3 attributes. The renderer is counted. Last is the tooltip text.
  var listStore = listStoreNew(5, TypeString, TypeString, TypeString,
                                  TypeString, TypeString)
  assert(listStore != nil)
  win.errorListWidget.setModel(liststore)
  win.errorListWidget.show()
  errorListTab.show()

  #addError(TETError, "type mistmatch:\n expected blah\n got: proc asd();",
  #  "file.nim", "190", "5")


proc initTAndBP(MainBox: PBox) =
  # This init's the HPaned, which splits the sourceViewTabs
  # and the BottomPanelTabs
  initSourceViewTabs()
  initBottomTabs()
  
  var TAndBPVPaned = vpanedNew()
  tandbpVPaned.pack1(win.sourceViewTabs, resize=True, shrink=False)
  tandbpVPaned.pack2(win.bottomPanelTabs, resize=False, shrink=False)
  MainBox.packStart(TAndBPVPaned, True, True, 0)
  tandbpVPaned.setPosition(win.settings.VPanedPos)
  TAndBPVPaned.show()

proc initFindBar(MainBox: PBox) =
  # Create a fixed container
  win.findBar = HBoxNew(False, 0)
  win.findBar.setSpacing(4)

  # Add a Label 'Find'
  var findLabel = labelNew("Find:")
  win.findBar.packStart(findLabel, False, False, 0)
  findLabel.show()

  # Add a (find) text entry
  win.findEntry = entryNew()
  win.findBar.packStart(win.findEntry, False, False, 0)
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
  win.findBar.packStart(win.replaceLabel, False, False, 0)
  
  # Add a (replace) text entry 
  # - This Is only shown when the 'Search & Replace'(CTRL + H) is shown
  win.replaceEntry = entryNew()
  win.findBar.packStart(win.replaceEntry, False, False, 0)
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
  var closeBox = hboxNew(False, 0)
  closeBtn.add(closeBox)
  closeBox.show()
  closeBox.add(closeImage)
  closeImage.show()
  discard closeBtn.signalConnect("clicked", 
             SIGNAL_FUNC(aporia.closeBtn_Clicked), nil)
  win.findBar.packEnd(closeBtn, False, False, 2)
  closeBtn.show()
  
  # Extra button - When clicked shows a menu with options like 'Use regex'
  var extraBtn = buttonNew()
  var extraImage = imageNewFromStock(STOCK_PROPERTIES, ICON_SIZE_SMALL_TOOLBAR)

  var extraBox = hboxNew(False, 0)
  extraBtn.add(extraBox)
  extraBox.show()
  extraBox.add(extraImage)
  extraImage.show()
  discard extraBtn.signalConnect("clicked", 
             SIGNAL_FUNC(aporia.extraBtn_Clicked), nil)
  win.findBar.packEnd(extraBtn, False, False, 0)
  extraBtn.show()
  
  MainBox.packStart(win.findBar, False, False, 0)
  #win.findBar.show()

proc initGoLineBar(MainBox: PBox) =
  # Create a fixed container
  win.goLineBar.bar = HBoxNew(False, 0)
  win.goLineBar.bar.setSpacing(4)

  # Add a Label 'Go to line'
  var goLineLabel = labelNew("Go to line:")
  win.goLineBar.bar.packStart(goLineLabel, False, False, 0)
  goLineLabel.show()

  # Add a text entry
  win.goLineBar.entry = entryNew()
  win.goLineBar.bar.packStart(win.goLineBar.entry, False, False, 0)
  discard win.goLineBar.entry.signalConnect("changed", SIGNAL_FUNC(
                                      goLine_changed), nil)
  win.goLineBar.entry.show()
  
  # Right side ...
  
  # Close button - With a close stock image
  var closeBtn = buttonNew()
  var closeImage = imageNewFromStock(STOCK_CLOSE, ICON_SIZE_SMALL_TOOLBAR)
  var closeBox = hboxNew(False, 0)
  closeBtn.add(closeBox)
  closeBox.show()
  closeBox.add(closeImage)
  closeImage.show()
  discard closeBtn.signalConnect("clicked", 
             SIGNAL_FUNC(aporia.goLineClose_Clicked), nil)
  win.goLineBar.bar.packEnd(closeBtn, False, False, 2)
  closeBtn.show()

  MainBox.packStart(win.goLineBar.bar, False, False, 0)

proc initStatusBar(MainBox: PBox) =
  win.bottomBar = statusbarNew()
  MainBox.packStart(win.bottomBar, False, False, 0)
  win.bottomBar.show()
  
  win.bottomProgress = progressBarNew()
  win.bottomProgress.hide()
  win.bottomProgress.setText("Executing...")
  win.bottomBar.packEnd(win.bottomProgress, false, false, 0)
  
  discard win.bottomBar.push(0, "Line: 0 Column: 0")

proc initTempStuff() =
  win.tempStuff.lastSaveDir = ""
  win.tempStuff.stopSBUpdates = false
  win.tempStuff.execMode = execNone

  win.tempStuff.ifSuccess = ""
  win.tempStuff.compileSuccess = false

  win.tempStuff.recentFileMenuItems = @[]

  win.tempStuff.compilationErrorBuffer = ""
  win.tempStuff.errorList = @[]
  win.tempStuff.lastTab = 0

proc initControls() =
  # Load up the language style
  var langMan = languageManagerGetDefault()
  var langManPaths: seq[string] = @[os.getAppDir() / langSpecs]
  
  var defLangManPaths = langMan.getSearchPath()
  for i in 0..len(defLangManPaths.cstringArrayToSeq)-1:
    if deflangManPaths[i] == nil: echo("bazinga")
    langManPaths.add($defLangManPaths[i])
    
  var newLangPaths = allocCStringArray(langManPaths)
  langMan.setSearchPath(newLangPaths)
  deallocCStringArray(newLangPaths)
  var nimLang = langMan.getLanguage("nimrod")
  win.nimLang = nimLang
  
  # Load the scheme
  var schemeMan = schemeManagerGetDefault()
  schemeMan.appendSearchPath(os.getAppDir() / styles)
  win.scheme = schemeMan.getScheme(win.settings.colorSchemeID)
  
  # Window
  win.w = windowNew(gtk2.WINDOW_TOPLEVEL)
  win.w.setDefaultSize(win.settings.winWidth, win.settings.winHeight)
  win.w.setTitle("Aporia")
  if win.settings.winMaximized: win.w.maximize()
  
  win.w.show() # The window has to be shown before
               # setting the position of the VPaned so that
               # it gets set correctly, when the window is maximized.
    
  discard win.w.signalConnect("destroy", SIGNAL_FUNC(aporia.destroy), nil)
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
  
  # MainBox (vbox)
  var MainBox = vboxNew(False, 0)
  win.w.add(MainBox)
  
  initTopMenu(MainBox)
  initToolBar(MainBox)
  initTAndBP(MainBox)
  initFindBar(MainBox)
  initGoLineBar(MainBox)
  initStatusBar(MainBox)
  
  MainBox.show()
  if confParseFail:
    dialogs.warning(win.w, "Error parsing config file, using default settings.")

proc afterInit() =
  win.Tabs[0].sourceView.grabFocus()

var versionReply = checkVersion(GTKVerReq[0], GTKVerReq[1], GTKVerReq[2])
if versionReply != nil:
  # Incorrect GTK version.
  quit("Aporia requires GTK $#.$#.$#. Call to check_version failed with: $#" %
       [$GTKVerReq[0], $GTKVerReq[1], $GTKVerReq[2], $versionReply], QuitFailure)

createProcessThreads()
nimrod_init()
initControls()
afterInit()
main()
