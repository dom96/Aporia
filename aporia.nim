#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import glib2, gtk2, gdk2, gtksourceview, dialogs, os, pango, osproc, strutils
import pegs, streams
import settings, types, cfg, search, suggest

{.push callConv:cdecl.}

const
  NimrodProjectExt = ".nimprj"
  GTKVerReq = (2, 12, 0) # Version of GTK required for Aporia to run.

var win: types.MainWin
win.Tabs = @[]

search.win = addr(win)

var lastSession: seq[string] = @[]

var confParseFail = False # This gets set to true
                          # When there is an error parsing the config

# Load the settings
try:
  win.settings = cfg.load(lastSession)
except ECFGParse:
  # TODO: Make the dialog show the exception
  confParseFail = True
  win.settings = cfg.defaultSettings()
except EIO:
  win.settings = cfg.defaultSettings()

proc echod[T](s: openarray[T]) =
  when defined(debug):
    for i in items(s): stdout.write(i)
    echo()
    
proc getProjectTab(): int = 
  for i in 0..high(win.tabs): 
    if win.tabs[i].filename.endswith(NimrodProjectExt): return i

proc saveTab(tabNr: int, startpath: string) =
  if tabNr < 0: return
  if win.Tabs[tabNr].saved: return
  var path = ""
  if win.Tabs[tabNr].filename == "":
    path = ChooseFileToSave(win.w, startpath) 
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
      var name = extractFilename(path)
      
      var cTab = win.Tabs[tabNr]
      cTab.label.setText(name)
    else:
      error(win.w, "Unable to write to file")  

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

proc delete_event(widget: PWidget, event: PEvent, user_data: pgpointer): bool =
  var quit = True
  for i in low(win.Tabs)..len(win.Tabs)-1:
    if not win.Tabs[i].saved:
      var askSave = dialogNewWithButtons("", win.w, 0,
                            STOCK_SAVE, RESPONSE_ACCEPT, STOCK_CANCEL, 
                            RESPONSE_CANCEL,
                            "Close without saving", RESPONSE_REJECT, nil)
      askSave.setTransientFor(win.w)
      # TODO: Make this dialog look better
      var label = labelNew(win.Tabs[i].filename & 
          " is unsaved, would you like to save it ?")
      askSave.vbox.pack_start(label, False, False, 0)
      label.show()

      var resp = askSave.run()
      gtk2.destroy(PWidget(askSave))
      case resp
      of RESPONSE_ACCEPT:
        saveTab(i, os.splitFile(win.tabs[i].filename).dir)
        quit = True
      of RESPONSE_CANCEL:
        quit = False
        break
      of RESPONSE_REJECT:
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
  if widgetRealized(win.suggest.dialog):
    var current = win.SourceViewTabs.getCurrentPage()
    var tab     = win.Tabs[current]
    var start: TTextIter
    # Get the iter at the cursor position.
    tab.buffer.getIterAtMark(addr(start), tab.buffer.getInsert())
    moveSuggest(win, addr(start), tab)

  return False

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

proc onCloseTab(btn: PButton, user_data: PWidget) =
  if win.sourceViewTabs.getNPages() > 1:
    var tab = win.sourceViewTabs.pageNum(user_data)
    win.sourceViewTabs.removePage(tab)

    win.Tabs.delete(tab)

proc onSwitchTab(notebook: PNotebook, page: PNotebookPage, pageNum: guint, 
                 user_data: pgpointer) =
  if win.Tabs.len()-1 >= pageNum:
    win.w.setTitle("Aporia IDE - " & win.Tabs[pageNum].filename)

proc createTabLabel(name: string, t_child: PWidget): tuple[box: PWidget,
                    label: PLabel] =
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
  return (box, label)

proc changed(buffer: PTextBuffer, user_data: pgpointer) =
  # Update the 'Line & Column'
  #updateStatusBar(buffer)

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
  var key = $keyval_name(event.keyval)
  case key.toLower()
  of "period":
    if win.settings.suggestFeature:
      var current = win.SourceViewTabs.getCurrentPage()
      var tab     = win.Tabs[current]
      var start: TTextIter
      # Get the iter at the cursor position.
      tab.buffer.getIterAtMark(addr(start), tab.buffer.getInsert())
      if win.populateSuggest(addr(start), tab):
        win.suggest.dialog.show()
        moveSuggest(win, addr(start), tab)
        win.Tabs[current].sourceView.grabFocus()
        assert(win.Tabs[current].sourceView.isFocus())
        win.w.present()
  of "up", "down":
    if win.settings.suggestFeature and widgetRealized(win.suggest.dialog):
      var selection = win.suggest.treeview.getSelection()
      var selectedIter: TTreeIter
      var TreeModel = win.suggest.TreeView.getModel()
      if selection.getSelected(cast[PPGtkTreeModel](addr(TreeModel)),
                               addr(selectedIter)):
        var selectedPath = TreeModel.getPath(addr(selectedIter))

        var moved = False
        if key.toLower() == "up":
          moved = prev(selectedPath)
        elif key.toLower() == "down":
          moved = True
          next(selectedPath)
        if moved:
          # selectedPath is now the next or prev path.
          selection.selectPath(selectedPath)
          win.suggest.treeview.scroll_to_cell(selectedPath, nil, False, 0.5, 0.5)
      else:
        # No item selected, select the first one.
        selection.selectPath(tree_path_new_first())
      
      # Return true to stop this event from moving the cursor down in the
      # source view.
      return True
  of "return", "space", "tab":
    if win.settings.suggestFeature and widgetRealized(win.suggest.dialog):
      var selection = win.suggest.treeview.getSelection()
      var selectedIter: TTreeIter
      var TreeModel = win.suggest.TreeView.getModel()
      if selection.getSelected(cast[PPGtkTreeModel](addr(TreeModel)),
                               addr(selectedIter)):
        var selectedPath = TreeModel.getPath(addr(selectedIter))
        var index = selectedPath.getIndices()[]
        var name = win.suggest.items[index].name
        # We have the name of the item. Now insert it into the TextBuffer.
        var currentTab = win.SourceViewTabs.getCurrentPage()
        win.Tabs[currentTab].buffer.insertAtCursor(name, len(name))
        
        # Now hide the suggest dialog and clear the items.
        win.suggest.dialog.hide()
        win.suggest.clear()
        
        return True
  else:
    echod("Key pressed: ", key)

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

  var font = font_description_from_string(win.settings.font)
  SourceView.modifyFont(font)
  
  scrollWindow.add(SourceView)
  SourceView.show()

  buffer.setHighlightMatchingBrackets(
      win.settings.highlightMatchingBrackets)
  
  # UGLY workaround for yet another compiler bug:
  discard gsignalConnect(buffer, "mark-set", 
                         GCallback(aporia.cursorMoved), nil)
  discard gsignalConnect(buffer, "changed", GCallback(aporia.changed), nil)
  discard gsignalConnect(sourceView, "key-press-event", 
                         GCallback(SourceViewKeyPress), nil)

  # -- Set the syntax highlighter scheme
  buffer.setScheme(win.scheme)

proc addTab(name, filename: string) =
  ## Adds a tab, if filename is not "" reads the file. And sets
  ## the tabs SourceViews text to that files contents.
  assert(win.nimLang != nil)
  var buffer: PSourceBuffer = sourceBufferNew(win.nimLang)

  if filename != nil and filename != "":
    var lang = win.langMan.guessLanguage(filename, nil)
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
      buffer.set_text(file, len(file))
    except EIO:
      echo("Can't open ", filename)
      
    # Enable the undo/redo manager.
    buffer.end_not_undoable_action()
      
    # Get the name.ext of the filename, for the tabs title
    nam = extractFilename(filename)
  
  # Init the sourceview
  var sourceView: PSourceView
  var scrollWindow: PScrolledWindow
  initSourceView(sourceView, scrollWindow, buffer)

  var (TabLabel, labelText) = createTabLabel(nam, scrollWindow)
  # Add a tab
  discard win.SourceViewTabs.appendPage(scrollWindow, TabLabel)

  var nTab: Tab
  nTab.buffer = buffer
  nTab.sourceView = sourceView
  nTab.label = labelText
  nTab.saved = (filename != "")
  nTab.filename = filename
  win.Tabs.add(nTab)

  PTextView(SourceView).setBuffer(nTab.buffer)

# GTK Events Contd.
# -- TopMenu & TopBar

proc newFile(menuItem: PMenuItem, user_data: pgpointer) =
  addTab("", "")
  win.sourceViewTabs.setCurrentPage(win.Tabs.len()-1)
  
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
        addTab("", f)
      except EIO:
        error(win.w, "Unable to read from file")
    # Switch to the newly created tab
    win.sourceViewTabs.setCurrentPage(win.Tabs.len()-1)
  
proc saveFile_Activate(menuItem: PMenuItem, user_data: pgpointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  saveTab(current, os.splitFile(win.tabs[current].filename).dir)

proc saveFileAs_Activate(menuItem: PMenuItem, user_data: pgpointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  var (filename, saved) = (win.Tabs[current].filename, win.Tabs[current].saved)

  win.Tabs[current].saved = False
  win.Tabs[current].filename = ""
  saveTab(current, os.splitFile(filename).dir)
  # If the user cancels the save file dialog. Restore the previous filename
  # and saved state
  if win.Tabs[current].filename == "":
    win.Tabs[current].filename = filename
    win.Tabs[current].saved = saved

proc undo(menuItem: PMenuItem, user_data: pgpointer) = 
  var current = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[current].buffer.canUndo():
    win.Tabs[current].buffer.undo()
  
proc redo(menuItem: PMenuItem, user_data: pgpointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[current].buffer.canRedo():
    win.Tabs[current].buffer.redo()
    
proc find_Activate(menuItem: PMenuItem, user_data: pgpointer) = 
  # Get the selected text, and set the findEntry to it.
  var currentTab = win.SourceViewTabs.getCurrentPage()
  var insertIter: TTextIter
  win.Tabs[currentTab].buffer.getIterAtMark(addr(insertIter), 
                                      win.Tabs[currentTab].buffer.getInsert())
  var insertOffset = addr(insertIter).getOffset()
  
  var selectIter: TTextIter
  win.Tabs[currentTab].buffer.getIterAtMark(addr(selectIter), 
                win.Tabs[currentTab].buffer.getSelectionBound())
  var selectOffset = addr(selectIter).getOffset()
  
  if insertOffset != selectOffset:
    var text = win.Tabs[currentTab].buffer.getText(addr(insertIter), 
                                                   addr(selectIter), false)
    win.findEntry.setText(text)

  win.findBar.show()
  win.findEntry.grabFocus()
  win.replaceEntry.hide()
  win.replaceLabel.hide()
  win.replaceBtn.hide()
  win.replaceAllBtn.hide()

proc replace_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  win.findBar.show()
  win.findEntry.grabFocus()
  win.replaceEntry.show()
  win.replaceLabel.show()
  win.replaceBtn.show()
  win.replaceAllBtn.show()
  
proc settings_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  settings.showSettings(win)
  
proc viewBottomPanel_Toggled(menuitem: PCheckMenuItem, user_data: pgpointer) =
  win.settings.bottomPanelVisible = menuitem.itemGetActive()
  if win.settings.bottomPanelVisible:
    win.bottomPanelTabs.show()
  else:
    win.bottomPanelTabs.hide()

var
  pegLineError = peg"{[^(]*} '(' {\d+} ', ' \d+ ') Error:' \s* {.*}"
  pegLineWarning = peg"{[^(]*} '(' {\d+} ', ' \d+ ') ' ('Warning:'/'Hint:') \s* {.*}"
  pegOtherError = peg"'Error:' \s* {.*}"
  pegSuccess = peg"'Hint: operation successful'.*"

proc addText(textView: PTextView, text: string,
             colorTag: PTextTag = nil, scroll: bool = true) =
  if text != nil:
    var iter: TTextIter
    textView.getBuffer().getEndIter(addr(iter))

    if colorTag == nil:
      textView.getBuffer().insert(addr(iter), text, len(text))
    else:
      textView.getBuffer().insertWithTags(addr(iter), text, len(text), colorTag,
                                          nil)
    if scroll:
      var endMark = textView.getBuffer().getMark("endMark")
      # Yay! With the use of marks; scrolling always occurs!
      textView.scrollToMark(endMark, 0.0, False, 0.0, 1.0)

proc createColor(textView: PTextView, name, color: string): PTextTag =
  var tagTable = textView.getBuffer().getTagTable()
  result = tagTable.tableLookup(name)
  if result == nil:
    result = textView.getBuffer().createTag(name, "foreground", color, nil)

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

{.pop.}

proc execProcThread() {.thread.} =
  while True:
    # Recv message
    var params = recv[ExecThrParams]()
    if params.execMode != ExecNone:
      # Execute the process
      var split = params.cmd.split()
      echod(repr(split))
      var exe = split[0]
      split.delete(0)
      var process = osProc.startProcess(exe, args = split,
                                    options = {poStderrToStdout, poUseShell})
      var procOut = process.outputStream
      while True:
        if peek() > 0:
          if recv[ExecThrParams]().execMode == ExecNone:
            break
        var line = procOut.readLine()
        if line == "": break
        # Send the `line` to the main thread.
        send(mainThreadId[ExecThrParams](), (line, params.execMode))

      if process.peekExitCode == -1:
        # TODO: Will this hang the thread forever?
        discard process.waitForExit()

      send(mainThreadId[ExecThrParams](), ("", ExecNone))
    else: echod("Process already stopped.")
  
proc execProcMT(cmd: string, mode: TExecMode, ifSuccess: string = "")
proc peekProcOutput(dummy: pointer): bool =
  result = True
  
  # Colors
  var normalTag = createColor(win.outputTextView, "normalTag", "#3d3d3d")
  var errorTag = createColor(win.outputTextView, "errorTag", "red")
  var warningTag = createColor(win.outputTextView, "warningTag", "darkorange")
  var successTag = createColor(win.outputTextView, "successTag", "darkgreen")
  
  var messages = peek()
  echod("Messages in inbox: ", $messages)
  if messages > 0:
    for i in 1 .. messages:
      var m = recv[ExecThrParams]()
      case m.execMode
      of ExecNimrod:
        if m[0] =~ pegLineError / pegOtherError:
          win.outputTextView.addText(m[0] & "\n", errorTag)
        elif m[0] =~ pegSuccess:
          win.outputTextView.addText(m[0] & "\n", successTag)
          if win.tempStuff.ifSuccess != "":
            # Terminate the worker thread, `execProcThread`.
            send(win.tempStuff.procExecThread.threadId(), ("", ExecNone))
            
            execProcMT(win.tempStuff.ifSuccess, ExecRun)
            return false
            
        elif m[0] =~ pegLineWarning:
          win.outputTextView.addText(m[0] & "\n", warningTag)
        else:
          win.outputTextView.addText(m[0] & "\n", normalTag)
      of ExecRun, ExecCustom:
        win.outputTextView.addText(m[0] & "\n", normalTag)
      of ExecNone:
        # Process no longer executing.
        # Don't return. Other messages might not be processed yet.
        win.tempStuff.procExecRunning = False
        result = False

proc execProcMT(cmd: string, mode: TExecMode, ifSuccess: string = "") =
  ## This function executes a process in a new thread, using only idle time
  ## to add the output of the process to the `outputTextview`.
  # Reset some things; and set some flags.
  win.tempStuff.ifSuccess = ifSuccess
  # Spawn the thread
  send(win.tempStuff.procExecThread.threadId(), (cmd, mode))
  win.tempStuff.procExecRunning = True
  # Add a function which will be called every 100 miliseconds.
  var tID = gTimeoutAdd(100, peekProcOutput, nil)
  echod("gTimeoutAdd id = ", $tID)

{.push callConv: cdecl.}

proc compileRun(currentTab: int, shouldRun: bool) =
  if win.Tabs[currentTab].filename.len == 0: return
  if win.tempStuff.procExecRunning:
    # TODO: Give some kind of a GUI message to the user.
    echod("Process already running!")
    return
  
  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()  

  var cmd = GetCmd(win.settings.nimrodCmd, win.Tabs[currentTab].filename)
  # Execute the compiled application if compiled successfully.
  # ifSuccess is the filename of the compiled app.
  var ifSuccess = ""
  if shouldRun:
    ifSuccess = changeFileExt(win.Tabs[currentTab].filename, os.ExeExt)
  execProcMT(cmd, ExecNimrod, ifSuccess)

proc CompileCurrent_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  saveFile_Activate(nil, nil)
  compileRun(win.SourceViewTabs.getCurrentPage(), false)
  
proc CompileRunCurrent_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  saveFile_Activate(nil, nil)
  compileRun(win.SourceViewTabs.getCurrentPage(), true)

proc CompileProject_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  saveAllTabs()
  compileRun(getProjectTab(), false)
  
proc CompileRunProject_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  saveAllTabs()
  compileRun(getProjectTab(), true)

proc RunCustomCommand(cmd: string) = 
  if win.tempStuff.procExecRunning:
    # TODO: Give some kind of a GUI message to the user.
    echod("Process already running!")
    return
  
  saveFile_Activate(nil, nil)
  var currentTab = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[currentTab].filename.len == 0 or cmd.len == 0: return
  
  # Clear the outputTextView
  win.outputTextView.getBuffer().setText("", 0)
  showBottomPanel()
  
  execProcMT(GetCmd(cmd, win.Tabs[currentTab].filename), ExecCustom)

proc RunCustomCommand1(menuitem: PMenuItem, user_data: pgpointer) =
  RunCustomCommand(win.settings.customCmd1)

proc RunCustomCommand2(menuitem: PMenuItem, user_data: pgpointer) =
  RunCustomCommand(win.settings.customCmd2)

proc RunCustomCommand3(menuitem: PMenuItem, user_data: pgpointer) =
  RunCustomCommand(win.settings.customCmd3)

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
  
  # Remove the text
  win.Tabs[currentTab].buffer.delete(addr(start), addr(theEnd))
  # Insert the replacement
  var text = getText(win.replaceEntry)
  win.Tabs[currentTab].buffer.insert(addr(start), text, len(text))
  
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

# GUI Initialization

proc createSuggestDialog() =
  ## Creates the suggest dialog, it does not show it.
  
  # I need 'gtk_window_set_skip_taskbar_hint'. Without it I have to make
  # a bit of a hack... which I uncommented for now. The suggest dialog will be
  # in the taskbar though.
  #win.suggest.dialog = dialogNew()
  win.suggest.dialog = windowNew(0)

  var vbox = vboxNew(False, 0)
  win.suggest.dialog.add(vbox)
  vbox.show()

  # TODO: Destroy actionArea?
  # Destroy the separator, don't need it.
  #win.suggest.dialog.separator.destroy()
  #win.suggest.dialog.separator = nil
  #win.suggest.dialog.actionArea.hide()
  #win.suggest.dialog.vbox.remove(win.suggest.dialog.actionArea)
  #echo(win.suggest.dialog.vbox.spacing)
  
  # Properties
  win.suggest.dialog.setDefaultSize(250, 150)
  
  win.suggest.dialog.setTransientFor(win.w)
  win.suggest.dialog.setDecorated(False)
  win.suggest.dialog.setSkipTaskbarHint(True)
  
  # TreeView & TreeModel
  # -- ScrolledWindow
  var scrollWindow = scrolledWindowNew(nil, nil)
  scrollWindow.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  vbox.packStart(scrollWindow, True, True, 0)
  scrollWindow.show()
  # -- TreeView
  win.suggest.treeView = treeViewNew()
  win.suggest.treeView.setHeadersVisible(False)
  scrollWindow.add(win.suggest.treeView)
  
  var textRenderer = cellRendererTextNew()
  # Renderer is number 0. That's why we count from 1.
  var textColumn   = treeViewColumnNewWithAttributes("Title", textRenderer,
                     "markup", 1, "foreground", 2, nil)
  discard win.suggest.treeView.appendColumn(textColumn)
  # -- ListStore
  # There are 3 attributes. The renderer is counted.
  var listStore = listStoreNew(3, TypeString, TypeString, TypeString)
  assert(listStore != nil)
  win.suggest.treeview.setModel(liststore)
  win.suggest.treeView.show()
  
  # -- Append some items.
  #win.addSuggestItem("Test!", "<b>Tes</b>t!")
  #win.addSuggestItem("Test2!", "Test2!", "#ff0000")
  #win.addSuggestItem("Test3!")
  win.suggest.items = @[]
  #win.suggest.dialog.show()


proc createAccelMenuItem(toolsMenu: PMenu, accGroup: PAccelGroup, 
                         label: string, acc: gint,
                         action: proc (i: PMenuItem, p: pgpointer)) = 
  var result = menu_item_new(label)
  result.addAccelerator("activate", accGroup, acc, 0, ACCEL_VISIBLE)
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
  var FileMenu = menuNew()

  var NewMenuItem = menu_item_new("New") # New
  FileMenu.append(NewMenuItem)
  show(NewMenuItem)
  discard signal_connect(NewMenuItem, "activate", 
                          SIGNAL_FUNC(newFile), nil)

  createSeparator(FileMenu)

  var OpenMenuItem = menu_item_new("Open...") # Open...
  # CTRL + O
  OpenMenuItem.add_accelerator("activate", accGroup, 
                  KEY_o, CONTROL_MASK, ACCEL_VISIBLE) 
  FileMenu.append(OpenMenuItem)
  show(OpenMenuItem)
  discard signal_connect(OpenMenuItem, "activate", 
                          SIGNAL_FUNC(aporia.openFile), nil)
  
  var SaveMenuItem = menu_item_new("Save") # Save
  # CTRL + S
  SaveMenuItem.add_accelerator("activate", accGroup, 
                  KEY_s, CONTROL_MASK, ACCEL_VISIBLE) 
  FileMenu.append(SaveMenuItem)
  show(SaveMenuItem)
  discard signal_connect(SaveMenuItem, "activate", 
                          SIGNAL_FUNC(saveFile_activate), nil)

  var SaveAsMenuItem = menu_item_new("Save As...") # Save as...

  SaveAsMenuItem.add_accelerator("activate", accGroup, 
                  KEY_s, CONTROL_MASK or gdk2.SHIFT_MASK, ACCEL_VISIBLE) 
  FileMenu.append(SaveAsMenuItem)
  show(SaveAsMenuItem)
  discard signal_connect(SaveAsMenuItem, "activate", 
                          SIGNAL_FUNC(saveFileAs_Activate), nil)
  
  var FileMenuItem = menuItemNewWithMnemonic("_File")

  FileMenuItem.setSubMenu(FileMenu)
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
  
  win.viewBottomPanelMenuItem = check_menu_item_new("Bottom Panel")
  PCheckMenuItem(win.viewBottomPanelMenuItem).itemSetActive(
         win.settings.bottomPanelVisible)
  win.viewBottomPanelMenuItem.add_accelerator("activate", accGroup, 
                  KEY_f9, CONTROL_MASK, ACCEL_VISIBLE) 
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
  createSeparator(ToolsMenu)
  createAccelMenuItem(ToolsMenu, accGroup, "Run custom command 1", 
                      KEY_F1, aporia.RunCustomCommand1)
  createAccelMenuItem(ToolsMenu, accGroup, "Run custom command 2", 
                      KEY_F2, aporia.RunCustomCommand2)
  createAccelMenuItem(ToolsMenu, accGroup, "Run custom command 3", 
                      KEY_F3, aporia.RunCustomCommand3)
  
  var ToolsMenuItem = menuItemNewWithMnemonic("_Tools")
  
  ToolsMenuItem.setSubMenu(ToolsMenu)
  ToolsMenuItem.show()
  TopMenu.append(ToolsMenuItem)
  
  # Help menu
  MainBox.packStart(TopMenu, False, False, 0)
  TopMenu.show()

proc initToolBar(MainBox: PBox) =
  # TopBar(ToolBar)
  var TopBar = toolbarNew()
  TopBar.setStyle(TOOLBAR_ICONS)
  
  var NewFileItem = TopBar.insertStock(STOCK_NEW, "New File",
                      "New File", SIGNAL_FUNC(aporia.newFile), nil, 0)
  TopBar.appendSpace()
  var OpenItem = TopBar.insertStock(STOCK_OPEN, "Open",
                      "Open", SIGNAL_FUNC(aporia.openFile), nil, -1)
  var SaveItem = TopBar.insertStock(STOCK_SAVE, "Save",
                      "Save", SIGNAL_FUNC(saveFile_Activate), nil, -1)
  TopBar.appendSpace()
  var UndoItem = TopBar.insertStock(STOCK_UNDO, "Undo", 
                      "Undo", SIGNAL_FUNC(aporia.undo), nil, -1)
  var RedoItem = TopBar.insertStock(STOCK_REDO, "Redo",
                      "Redo", SIGNAL_FUNC(aporia.redo), nil, -1)
  
  MainBox.packStart(TopBar, False, False, 0)
  TopBar.show()
  
proc initSourceViewTabs() =
  win.SourceViewTabs = notebookNew()
  discard win.SourceViewTabs.signalConnect(
          "switch-page", SIGNAL_FUNC(onSwitchTab), nil)
  win.SourceViewTabs.set_scrollable(True)
  
  win.SourceViewTabs.show()
  if lastSession.len != 0:
    for i in 0 .. len(lastSession)-1:
      var splitUp = lastSession[i].split('|')
      var (filename, offset) = (splitUp[0], splitUp[1])
      addTab("", filename)
      
      var iter: TTextIter
      win.Tabs[i].buffer.getIterAtOffset(addr(iter), offset.parseInt())
      win.Tabs[i].buffer.moveMarkByName("insert", addr(iter))
      win.Tabs[i].buffer.moveMarkByName("selection_bound", addr(iter))
      
      # TODO: Fix this..... :(
      discard PTextView(win.Tabs[i].sourceView).
          scrollToIter(addr(iter), 0.25, true, 0.0, 0.0)
  else:
    addTab("", "")
  
  # This doesn't work :\
  win.Tabs[0].sourceView.grabFocus()

  
proc initBottomTabs() =
  win.bottomPanelTabs = notebookNew()
  if win.settings.bottomPanelVisible:
    win.bottomPanelTabs.show()
  
  # output tab
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
  win.findBar.show()

proc initStatusBar(MainBox: PBox) =
  win.bottomBar = statusbarNew()
  MainBox.packStart(win.bottomBar, False, False, 0)
  win.bottomBar.show()
  
  discard win.bottomBar.push(0, "Line: 0 Column: 0")
  
proc initControls() =
  # Load up the language style
  win.langMan = languageManagerGetDefault()
  var langpaths: array[0..1, cstring] = 
          [cstring(os.getApplicationDir() / langSpecs), nil]
  win.langMan.setSearchPath(addr(langpaths))
  var nimLang = win.langMan.getLanguage("nimrod")
  win.nimLang = nimLang
  
  # Load the scheme
  var schemeMan = schemeManagerGetDefault()
  var schemepaths: array[0..1, cstring] =
          [cstring(os.getApplicationDir() / styles), nil]
  schemeMan.setSearchPath(addr(schemepaths))
  win.scheme = schemeMan.getScheme(win.settings.colorSchemeID)
  
  # Window
  win.w = windowNew(gtk2.WINDOW_TOPLEVEL)
  win.w.setDefaultSize(win.settings.winWidth, win.settings.winHeight)
  win.w.setTitle("Aporia IDE")
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
  
  # Suggest dialog
  createSuggestDialog()
  
  # MainBox (vbox)
  var MainBox = vboxNew(False, 0)
  win.w.add(MainBox)
  
  initTopMenu(MainBox)
  initToolBar(MainBox)
  initTAndBP(MainBox)
  initFindBar(MainBox)
  initStatusBar(MainBox)
  
  MainBox.show()
  if confParseFail:
    dialogs.warning(win.w, "Error parsing config file, using default settings.")

{.pop.}
proc NimThreadsInit() =
  # Start the procExecThread
  win.tempStuff.procExecThread.createThread(execProcThread)
{.push callConv: cdecl.}

var versionReply = checkVersion(GTKVerReq[0], GTKVerReq[1], GTKVerReq[2])
if versionReply != nil:
  # Incorrect GTK version.
  quit("Aporia requires GTK $#.$#.$#. Call to check_version failed with: $#" %
       [$GTKVerReq[0], $GTKVerReq[1], $GTKVerReq[2], $versionReply], QuitFailure)

NimThreadsInit()
nimrod_init()
initControls()
main()
