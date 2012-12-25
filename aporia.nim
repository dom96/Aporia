#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Stdlib imports:
import glib2, gtk2, gdk2, gtksourceview, dialogs, os, pango, osproc, strutils
import pegs, streams, times, parseopt, parseutils, asyncio, sockets, encodings
# Local imports:
import settings, utils, cfg, search, suggest, AboutDialog, processes,
       CustomStatusBar

{.push callConv:cdecl.}

const
  NimrodProjectExt = ".nimprj"
  GTKVerReq = (2'i32, 18'i32, 0'i32) # Version of GTK required for Aporia to run.
  aporiaVersion = "0.1.3"
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
        win.Tabs[tabNr].buffer.setHighlightSyntax(True)
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
        win.statusbar.setTemp("File saved successfully.", UrgSuccess, 5000)
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

      if win.settings.suggestFeature and win.suggest.shown:
        win.filterSuggest()
        win.doMoveSuggest()

proc SourceViewMousePress(sourceView: PWidget, ev: PEvent, usr: gpointer): bool=
  win.suggest.hide()

proc addTab(name, filename: string, setCurrent: bool = True, encoding = "utf-8")
proc SourceView_PopulatePopup(entry: PTextView, menu: PMenu, u: pointer) =
  if win.getCurrentLanguage() == "nimrod":
    createSeparator(menu)
    createMenuItem(menu, "Go to definition...",
      proc (i: PMenuItem, p: pointer) =
        let currentPage = win.sourceViewTabs.getCurrentPage()
        let tab = win.Tabs[currentPage]
        var cursor: TTextIter
        tab.buffer.getIterAtMark(addr(cursor), tab.buffer.getInsert())
        var def: TSuggestItem
        if findDef(tab.filename, getLine(addr cursor), 
             getLineOffset(addr cursor), def):
          
          let existingTab = win.findTab(def.file, true)
          if existingTab != -1:
            win.sourceViewTabs.setCurrentPage(existingTab.gint)
          else:
            addTab("", def.file, true)
          
          let currentPage = win.sourceViewTabs.getCurrentPage()
          # Go to that line/col
          var iter: TTextIter
          win.tabs[currentPage].buffer.getIterAtLineIndex(addr(iter),
              def.line-1, def.col-1)
          
          win.tabs[currentPage].buffer.placeCursor(addr(iter))
          
          win.scrollToInsert()
          
          echod(def.repr())
        else:
          echod("Found nothing")
    )

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
  SourceView.setSmartHomeEnd(SmartHomeEndBefore)
  discard signalConnect(SourceView, "button-press-event",
                        signalFunc(SourceViewMousePress), nil)
  discard gSignalConnect(sourceView, "populate-popup",
                         GCallback(sourceViewPopulatePopup), nil)

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
  

proc addTab(name, filename: string, setCurrent: bool = True, encoding = "utf-8") =
  ## Adds a tab. If filename is not "", a file is read and set as the content
  ## of the new tab. If name is "" it will be either "Unknown" or the last part
  ## of the filename.
  ## If filename doesn't exist EIO is raised.
  assert(win.nimLang != nil)
  
  var buffer: PSourceBuffer = sourceBufferNew(win.nimLang)
  
  if filename != nil and filename != "":
    if setCurrent:
      # If a tab with the same filename already exists select it.
      var existingTab = win.findTab(filename)
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
    
    # Read the file first so that we can affirm its encoding.
    try:
      var fileTxt: string = readFile(filename)
      if encoding.ToLower() != "utf-8":
        fileTxt = convert(fileTxt, "UTF-8", encoding)
      if not g_utf8_validate(fileTxt, fileTxt.len().gssize, nil):
        win.tempStuff.pendingFilename = filename
        win.statusbar.setTemp("Could not open file with " &
                              encoding & " encoding.", UrgError, 5000)
        win.infobar.show()
        return
      # Read in the file.
      buffer.set_text(fileTxt, len(fileTxt).int32)
    except EIO: raise
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
  if not win.settings.showCloseOnAllTabs:
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


proc newFile(menuItem: PMenuItem, user_data: pointer) = addTab("", "", True)
  
proc openFile(menuItem: PMenuItem, user_data: pointer) =
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
  
proc saveFile_Activate(menuItem: PMenuItem, user_data: pointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  var startpath = os.splitFile(win.tabs[current].filename).dir
  if startpath == "":
    startpath = win.tempStuff.lastSaveDir
  
  saveTab(current, startpath)

proc saveFileAs_Activate(menuItem: PMenuItem, user_data: pointer) =
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

proc undo(menuItem: PMenuItem, user_data: pointer) = 
  var current = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[current].buffer.canUndo():
    win.Tabs[current].buffer.undo()
  else:
    win.statusbar.setTemp("Nothing to undo.", UrgError, 5000)
  win.scrollToInsert()
  
proc redo(menuItem: PMenuItem, user_data: pointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[current].buffer.canRedo():
    win.Tabs[current].buffer.redo()
  else:
    win.statusbar.setTemp("Nothing to redo.", UrgError, 5000)
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
  
proc GoLine_Activate(menuitem: PMenuItem, user_data: pointer) =
  win.goLineBar.bar.show()
  win.goLineBar.entry.grabFocus()

proc CommentLines_Activate(menuitem: PMenuItem, user_data: pointer) =
  template cb(): expr = win.Tabs[currentPage].buffer
  var currentPage = win.sourceViewTabs.GetCurrentPage()
  var start, theEnd: TTextIter
  proc toggleSingle() =
    # start and end are the same line no.
    # get the whole
    var line = cb.getText(addr(start), addr(theEnd),
                  false)
    # Find first non-whitespace
    var locNonWS = ($line).skipWhitespace()
    # Check if the line is commented.
    let lineComment = win.tempStuff.commentSyntax.line
    if ($line)[locNonWS .. locNonWS+lineComment.len-1] == lineComment:
      # Line is commented
      var startCmntIter, endCmntIter: TTextIter
      cb.getIterAtLineOffset(addr(startCmntIter), (addr start).getLine(),
                             locNonWS.gint)
      cb.getIterAtLineOffset(addr(endCmntIter), (addr start).getLine(),
                             gint(locNonWS+lineComment.len))
      # Remove comment char(s)
      gtk2.delete(cb, addr(startCmntIter), addr(endCmntIter))
    else:
      var locNonWSIter: TTextIter
      cb.getIterAtLineOffset(addr(locNonWSIter), (addr start).getLine(),
                             locNonWS.gint)
      # Insert the line comment string.
      cb.insert(addr(locNonWSIter), lineComment, lineComment.len.gint)
  
  proc toggleMultiline() =
    (addr theEnd).moveToEndLine() # Move to end of line.
    var selectedTxt = cb.getText(addr(start), addr(theEnd), false)
    # Check if this language supports block comments.
    let blockStart = win.tempStuff.commentSyntax.blockStart
    let blockEnd   = win.tempStuff.commentSyntax.blockEnd
    if blockStart != "":
      var firstNonWS = ($selectedTxt).skipWhitespace()
      if ($selectedTxt)[firstNonWS .. firstNonWS+blockStart.len-1] == blockStart:
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
        gtk2.delete(cb, addr(startCmntIter), addr(endCmntIter))
        
        cb.getIterAtMark(addr(startCmntIter), blockEndMark)
        cb.getIterAtOffset(addr(endCmntIter), (addr startCmntIter).getOffset() +
                           gint(blockEnd.len))
        gtk2.delete(cb, addr(startCmntIter), addr(endCmntIter))
      else:
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
      # (# in the case of Nimrod) to it.
  
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

proc settings_Activate(menuitem: PMenuItem, user_data: pointer) =
  settings.showSettings(win)

proc viewToolBar_Toggled(menuitem: PCheckMenuItem, user_data: pointer) =
  win.settings.toolBarVisible = menuitem.itemGetActive()
  if win.settings.toolBarVisible:
    win.toolBar.show()
  else:
    win.toolBar.hide()

proc viewBottomPanel_Toggled(menuitem: PCheckMenuItem, user_data: pointer) =
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
    win.statusbar.setTemp("Process already running!", UrgError, 5000)
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

proc CompileCurrent_Activate(menuitem: PMenuItem, user_data: pointer) =
  let filename = saveForCompile(win.SourceViewTabs.getCurrentPage())
  compileRun(filename, false)
  
proc CompileRunCurrent_Activate(menuitem: PMenuItem, user_data: pointer) =
  let filename = saveForCompile(win.SourceViewTabs.getCurrentPage())
  compileRun(filename, true)

proc CompileProject_Activate(menuitem: PMenuItem, user_data: pointer) =
  let filename = saveAllForCompile(getProjectTab())
  compileRun(filename, false)
  
proc CompileRunProject_Activate(menuitem: PMenuItem, user_data: pointer) =
  let filename = saveAllForCompile(getProjectTab())
  compileRun(filename, true)

proc StopProcess_Activate(menuitem: PMenuItem, user_data: pointer) =

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
    win.statusbar.setTemp("No process running.", UrgError, 5000)

proc RunCustomCommand(cmd: string) = 
  if win.tempStuff.execMode != ExecNone:
    win.statusbar.setTemp("Process already running!", UrgError, 5000)
    return
  
  saveFile_Activate(nil, nil)
  var currentTab = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[currentTab].filename.len == 0 or cmd.len == 0: return
  
  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()
  
  execProcAsync(GetCmd(cmd, win.Tabs[currentTab].filename), ExecCustom)

proc RunCustomCommand1(menuitem: PMenuItem, user_data: pointer) =
  RunCustomCommand(win.settings.customCmd1)

proc RunCustomCommand2(menuitem: PMenuItem, user_data: pointer) =
  RunCustomCommand(win.settings.customCmd2)

proc RunCustomCommand3(menuitem: PMenuItem, user_data: pointer) =
  RunCustomCommand(win.settings.customCmd3)

proc RunCheck(menuItem: PMenuItem, user_data: pointer) =
  let filename = saveForCompile(win.SourceViewTabs.getCurrentPage())
  if filename.len == 0: return
  if win.tempStuff.execMode != ExecNone:
    win.statusbar.setTemp("Process already running!", UrgError, 5000)
    return
  
  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()

  var cmd = GetCmd("$findExe(nimrod) check $#", filename)
  execProcAsync(cmd, ExecNimrod)

proc memUsage_click(menuitem: PMenuItem, user_data: pointer) =
  echod("Memory usage: ")
  gMemProfile()
  var stats = "Memory usage: "
  stats.add gcGetStatistics()
  win.w.info(stats)

proc about_click(menuitem: PMenuItem, user_data: pointer) =
  # About dialog
  var aboutDialog = newAboutDialog("Aporia " & aporiaVersion, 
      "Aporia is an IDE for the \nNimrod programming language.",
      "Copyright (c) 2010-2012 Dominik Picheta")
  aboutDialog.show()

# -- Infobar
proc InfoBar_Response(infobar: PInfoBar, respID: gint, cb: pointer) =
  # (Encodings) info bar button pressed.
  var comboBox = cast[PComboBoxText](cb)
  assert win.tempStuff.pendingFilename != ""
  case respID
  of ResponseOK:
    let active = comboBox.getActive().int
    assert active >= 0 and active <= Windows1251.int
    comboBox.setActive(0) # Reset selection.
    infobar.hide()
    addTab("", win.tempStuff.pendingFilename, true,
           $TEncodingsAvailable(active))
    # addTab may set pendingFilename so we can't reset it here.
    # bad things shouldn't happen if it doesn't get reset though.
  of ResponseCancel:
    comboBox.setActive(0) # Reset selection.
    win.tempStuff.pendingFilename = ""
    infobar.hide()
  else: assert false

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
    let galloc = win.tabs[win.tabs.len-1].closeBtn.allocation
    if galloc.x == -1:
      # Use the label x instead
      let labelAlloc = win.tabs[win.tabs.len-1].label.allocation
      assert labelAlloc.x != -1
      if ev.x < labelAlloc.x.float: return # Didn't click on empty space.
    else:
      if ev.x < galloc.x.float: return # Didn't click on empty space.
    
    addTab("", "", true)

proc onSwitchTab(notebook: PNotebook, page: PNotebookPage, pageNum: guint, 
                 user_data: pgpointer) =
  # hide close button of last active tab
  if not win.settings.showCloseOnAllTabs and 
      win.tempStuff.lastTab < win.Tabs.len:
    win.Tabs[win.tempStuff.lastTab].closeBtn.hide()
  
  win.tempStuff.lastTab = pageNum
  updateMainTitle(pageNum)
  updateStatusBar(win.Tabs[pageNum].buffer)
  # Set the lastSavedDir
  if win.tabs.len > pageNum:
    if win.Tabs[pageNum].filename.len != 0:
      win.tempStuff.lastSaveDir = splitFile(win.Tabs[pageNum].filename).dir
  
  # Hide the suggest dialog
  win.suggest.hide()
  
  if not win.settings.showCloseOnAllTabs:
    # Show close button of tab
    win.Tabs[pageNum].closeBtn.show()

  # Get info about the current tabs language. Comment syntax etc.
  win.getCurrentLanguageComment(win.tempStuff.commentSyntax, pageNum)

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
          var existingTab = win.findTab(path)
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
  system.delete(win.Tabs, win.tempStuff.lastTab)
  win.Tabs.insert(oldPos, int(pageNum))
  
  win.tempStuff.lastTab = int(pageNum)

# -- Bottom tabs

proc errorList_RowActivated(tv: PTreeView, path: PTreePath, 
            column: PTreeViewColumn, d: pointer) =
  let selectedIndex = path.getIndices()[]
  let item = win.tempStuff.errorList[selectedIndex]
  var existingTab = win.findTab(item.file, false)
  if existingTab == -1 or item.file == "":
    win.statusbar.setTemp("Could not find correct tab.", UrgError, 5000)
  else:
    win.sourceViewTabs.setCurrentPage(int32(existingTab))
    
    # Move cursor to where the error is.
    var insertIndex = int32(item.column.parseInt)-1
    var selectionBound = int32(item.column.parseInt)
    if insertIndex < 0:
      insertIndex = 0
      selectionBound = 1
    
    var iter: TTextIter
    var iterPlus1: TTextIter 
    win.Tabs[existingTab].buffer.getIterAtLineOffset(addr(iter),
        int32(item.line.parseInt)-1, insertIndex)
    win.Tabs[existingTab].buffer.getIterAtLineOffset(addr(iterPlus1),
        int32(item.line.parseInt)-1, selectionBound)
    
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
  win.statusbar.setTemp("Replaced $1 matches." % $count, UrgNormal, 5000)
  
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

proc initTopMenu(MainBox: PBox) =
  # Create a accelerator group, used for shortcuts
  # like CTRL + S in SaveMenuItem
  var accGroup = accel_group_new()
  add_accel_group(win.w, accGroup)

  # TopMenu(MenuBar)
  var TopMenu = menuBarNew()
  
  # FileMenu
  win.FileMenu = menuNew()
  
  # New
  win.FileMenu.createAccelMenuItem(accGroup, "", KEY_n, newFile, ControlMask,
                                   StockNew)

  createSeparator(win.FileMenu)

  win.FileMenu.createAccelMenuItem(accGroup, "", KEY_o, openFile, ControlMask,
                                   StockOpen)
  
  win.FileMenu.createAccelMenuItem(accGroup, "", KEY_s, saveFile_activate, 
                                   ControlMask, StockSave)
  
  win.FileMenu.createAccelMenuItem(accGroup, "", KEY_s, saveFileAs_Activate,
                                   ControlMask or gdk2.ShiftMask, StockSaveAs)
  
  createSeparator(win.FileMenu)
  
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
  
  # Find/Find & Replace
  EditMenu.createAccelMenuItem(accGroup, "", KEY_f, aporia.find_Activate,
      ControlMask, StockFind)

  EditMenu.createAccelMenuItem(accGroup, "", KEY_h, aporia.replace_Activate,
      ControlMask, StockFindAndReplace)

  createSeparator(EditMenu)
  
  EditMenu.createAccelMenuItem(accGroup, "Go to line...", KEY_g, 
      GoLine_Activate, ControlMask, "")
  
  createSeparator(EditMenu)
  
  EditMenu.createAccelMenuItem(accGroup, "Comment/Uncomment line(s)", KEY_slash, 
      CommentLines_Activate, ControlMask, "")
  
  createSeparator(EditMenu)
  
  # Settings
  EditMenu.createImageMenuItem(StockPreferences, aporia.settings_Activate)
  
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
  
  HelpMenu.createImageMenuItem(StockAbout, aporia.About_click)
  
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

proc initInfoBar(MainBox: PBox) =
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
  vbox.packStart(messageLabel, False, False, 0)
  
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
  encodingsComboBox.setActive(UTF8.guint)
  encodingsComboBox.show()
  hbox.packStart(encodingsComboBox, false, false, 0)
  
  vbox.packStart(hbox, False, False, 10)
  var contentArea = win.infobar.getContentArea()
  contentArea.add(vbox)
  
  MainBox.packStart(win.infobar, False, False, 0)

  discard win.infobar.signalConnect("response",
         SIGNAL_FUNC(InfoBarResponse), encodingsComboBox)

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
  
  discard win.SourceViewTabs.signalConnect("button-press-event",
          SIGNAL_FUNC(onTabsPressed), nil)
  
  win.SourceViewTabs.show()
  if lastSession.len != 0 or loadFiles.len != 0:
    var count = 0
    for i in 0 .. lastSession.len-1:
      var splitUp = lastSession[i].split('|')
      var (filename, offset) = (splitUp[0], splitUp[1])
      if existsFile(filename):
        addTab("", filename, False)
      
        var iter: TTextIter
        # TODO: Save last cursor position as line and column offset combo.
        # This will help with int overflows which would happen more often with
        # a char offset.
        win.Tabs[count].buffer.getIterAtOffset(addr(iter), int32(offset.parseInt()))
        win.Tabs[count].buffer.placeCursor(addr(iter))
        
        var mark = win.Tabs[count].buffer.getInsert()
        
        # The reason why this didn't work was because the GtkWindow was being
        # shown too quickly.
        win.Tabs[count].sourceView.scrollToMark(mark, 0.25, False, 0.0, 0.0)
        inc(count)
      else: dialogs.error(win.w, "Could not restore file from session, file not found: " & filename)
    
    for f in loadFiles:
      if existsFile(f):
        var absPath = f
        if not isAbsolute(absPath):
          absPath = getCurrentDir() / f
        addTab("", absPath)
      else:
        dialogs.error(win.w, "Could not open " & f)
        quit(QuitFailure)
    
  else:
    addTab("", "", False)

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
  var font = font_description_from_string(win.settings.outputFont)
  win.outputTextView.modifyFont(font)
  
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
  win.findBar.packStart(findLabel, False, False, 5)
  findLabel.show()

  # Add a (find) text entry
  win.findEntry = entryNew()
  win.findBar.packStart(win.findEntry, True, True, 0)
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
  win.findBar.packStart(win.replaceEntry, True, True, 0)
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
  win.goLineBar.bar.packStart(goLineLabel, False, False, 5)
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
  win.tempStuff.pendingFilename = ""

{.pop.}
proc initSocket() =
  win.IODispatcher = newDispatcher()
  win.oneInstSock = AsyncSocket()
  win.oneInstSock.handleAccept =
    proc (s: PAsyncSocket) =
      var client: PAsyncSocket
      new(client)
      s.accept(client)
      client.handleRead =
        proc (c: PAsyncSocket) =
          var line = ""
          if c.recvLine(line):
            if line == "":
              c.close()
            elif line == "\c\L":
              win.w.present()
            else:
              var filePath = line
              if not filePath.isAbsolute():
                filePath = getCurrentDir() / filePath
              if existsFile(filepath):
                addTab("", filepath, true)
                win.w.present()
              else:
                win.w.error("File not found: " & filepath)
                win.w.present()
      win.IODispatcher.register(client)
      
  win.IODispatcher.register(win.oneInstSock)
  win.oneInstSock.bindAddr(TPort(win.settings.singleInstancePort.toU16), "localhost")
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
  initInfoBar(MainBox)
  initTAndBP(MainBox)
  initFindBar(MainBox)
  initGoLineBar(MainBox)
  #initStatusBar(MainBox)
  win.statusbar = initCustomStatusBar(mainBox)
  
  MainBox.show()
  if confParseFail:
    dialogs.warning(win.w, "Error parsing config file, using default settings.")

  # TODO: The fact that this call was above all initializations was because of
  # the VPaned position. I had to move it here because showing the Window
  # before initializing (I presume, could be another widget) the GtkSourceView
  # (maybe the ScrolledView) means that the stupid thing won't scroll on startup.
  # This took me a VERY long time to find.
  win.w.show() 

  when not defined(noSingleInstance):
    try:
      initSocket()
    except:
      echo getStackTrace()
      dialogs.warning(win.w, 
        "Unable to bind socket. Aporia will not " &
        "function properly as a single instance. Error was: " & getCurrentExceptionMsg())
    discard gTimeoutAddFull(GPriorityLow, 500, 
      proc (dummy: pointer): bool =
        result = win.IODispatcher.poll(5), nil, nil)

proc checkAlreadyRunning(): bool =
  result = false
  var client = socket()
  try:
    client.connect("localhost", TPort(win.settings.singleInstancePort.toU16))
  except EOS:
    return false
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

proc afterInit() =
  win.Tabs[0].sourceView.grabFocus()

var versionReply = checkVersion(GTKVerReq[0], GTKVerReq[1], GTKVerReq[2])
if versionReply != nil:
  # Incorrect GTK version.
  quit("Aporia requires GTK $#.$#.$#. Call to check_version failed with: $#" %
       [$GTKVerReq[0], $GTKVerReq[1], $GTKVerReq[2], $versionReply], QuitFailure)

when not defined(noSingleInstance):
  if checkAlreadyRunning():
    quit(QuitSuccess)

createProcessThreads()
nimrod_init()
initControls()
afterInit()
main()
