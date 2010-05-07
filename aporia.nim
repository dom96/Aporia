#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2010 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import glib2, gtk2, gdk2, gtksourceview, dialogs, os, pango, osproc, strutils
import pegs, streams
import settings, types, cfg
{.push callConv:cdecl.}

var win: types.MainWin
win.Tabs = @[]

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

# GTK Events
# -- w(PWindow)
proc destroy(widget: PWidget, data: pgpointer){.cdecl.} =
  # gather some settings
  win.settings.VPanedPos = PPaned(win.sourceViewTabs.getParent()).getPosition()
  win.settings.winWidth = win.w.allocation.width
  win.settings.winHeight = win.w.allocation.height

  # save the settings
  win.save()
  # then quit
  main_quit()
  
proc windowState_Changed(widget: PWidget, event: PEventWindowState, user_data: pgpointer) =
  win.settings.winMaximized = (event.newWindowState and WINDOW_STATE_MAXIMIZED) != 0

# -- SourceView(PSourceView) & SourceBuffer
proc updateStatusBar(buffer: PTextBuffer){.cdecl.} =
  if win.bottomBar != nil:  # Incase this event gets fired before
                            # bottomBar is initialized
    var row, col: gint
    var iter: TTextIter
    
    win.bottomBar.pop(0)
    
    buffer.getIterAtMark(addr(iter), buffer.getInsert())
    
    row = getLine(addr(iter)) + 1
    col = getLineOffset(addr(iter))
    
    discard win.bottomBar.push(0, "Line: " & $row & " Column: " & $col)
  
proc cursorMoved(buffer: PTextBuffer, location: PTextIter, 
                 mark: PTextMark, user_data: pgpointer){.cdecl.} =
  updateStatusBar(buffer)

proc onCloseTab(btn: PButton, user_data: PWidget) =
  if win.sourceViewTabs.getNPages() > 1:
    var tab = win.sourceViewTabs.pageNum(user_data)
    win.sourceViewTabs.removePage(tab)

    win.Tabs.delete(tab)

proc createTabLabel(name: string, t_child: PWidget): PWidget =
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
  return box
  
proc changed(buffer: PTextBuffer, user_data: pgpointer){.cdecl.} =
  # Update the 'Line & Column'
  updateStatusBar(buffer)

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
  
  var cTab = win.sourceViewTabs.getNthPage(current)
  win.sourceViewTabs.setTabLabel(cTab, createTabLabel(name, cTab))
  
# Other(Helper) functions

proc initSourceView(SourceView: var PWidget, scrollWindow: var PScrolledWindow,
                    buffer: var PSourceBuffer) =
  # This gets called by addTab
  # Each tabs creates a new SourceView
  # SourceScrolledWindow(ScrolledWindow)
  scrollWindow = scrolledWindowNew(nil, nil)
  scrollWindow.show()
  
  # SourceView(gtkSourceView)
  SourceView = sourceViewNew(buffer)
  PSourceView(SourceView).setInsertSpacesInsteadOfTabs(True)
  PSourceView(SourceView).setIndentWidth(win.settings.indentWidth)
  PSourceView(SourceView).setShowLineNumbers(win.settings.showLineNumbers)
  PSourceView(SourceView).setHighlightCurrentLine(win.settings.highlightCurrentLine)
  PSourceView(SourceView).setShowRightMargin(win.settings.rightMargin)

  var font = font_description_from_string(win.settings.font)
  SourceView.modifyFont(font)
  
  scrollWindow.add(SourceView)
  SourceView.show()
  # -- Set the syntax highlighter language
  buffer.setHighlightMatchingBrackets(
      win.settings.highlightMatchingBrackets)
  
  # UGLY workaround for yet another compiler bug:
  discard gsignalConnect(buffer, "mark-set", 
                         GCallback(aporia.cursorMoved), nil)
  discard gsignalConnect(buffer, "changed", GCallback(aporia.changed), nil)

  buffer.setLanguage(win.nimLang)
  buffer.setScheme(win.scheme)

proc addTab(name: string, filename: string) =
  ## Adds a tab, if filename is not "" reads the file. And sets
  ## the tabs SourceViews text to that files contents.
  var buffer: PSourceBuffer = sourceBufferNew(win.nimLang)

  var nam = name
  if nam == "": nam = "Untitled"
  if filename == "": nam.add(" *")
  elif filename != "" and name == "":
    # Load the file.
    var file: string = readFile(filename)
    if file != nil:
      buffer.set_text(file, len(file))
      
    # Get the name.ext of the filename, for the tabs title
    nam = extractFilename(filename)
  
  # Init the sourceview
  var sourceView: PWidget
  var scrollWindow: PScrolledWindow
  initSourceView(sourceView, scrollWindow, buffer)
  
  var TabLabel = createTabLabel(nam, scrollWindow)
  # Add a tab
  discard win.SourceViewTabs.appendPage(scrollWindow, TabLabel)

  var nTab: Tab
  nTab.buffer = buffer
  nTab.sourceView = sourceView
  nTab.saved = (filename == "")
  nTab.filename = filename
  win.tabs.add(nTab)

  PTextView(SourceView).setBuffer(nTab.buffer)

# GTK Events Contd.
# -- TopMenu & TopBar

proc newFile(menuItem: PMenuItem, user_data: pgpointer) =
  addTab("", "")
  win.sourceViewTabs.setCurrentPage(win.Tabs.len()-1)
  
proc openFile(menuItem: PMenuItem, user_data: pgpointer) =
  var path = ChooseFileToOpen(win.w)
  
  if path != "":
    try:
      addTab("", path)
      # Switch to the newly created tab
      win.sourceViewTabs.setCurrentPage(win.Tabs.len()-1)
    except EIO:
      error(win.w, "Unable to read from file")

proc saveFile(menuItem: PMenuItem, user_data: pgpointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  if current != -1:
    if not win.Tabs[current].saved:
      var path = ""
      if win.Tabs[current].filename == "":
        path = ChooseFileToSave(win.w)
      else: path = win.Tabs[current].filename
      
      if path != "":
        var buffer = PTextBuffer(win.Tabs[current].buffer)
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
          
          # Change the tab name and .Tabs.filename etc.
          win.Tabs[current].filename = path
          win.Tabs[current].saved = True
          var name = extractFilename(path)
          
          var cTab = win.sourceViewTabs.getNthPage(current)
          win.sourceViewTabs.setTabLabel(cTab, createTabLabel(name, cTab))
          
        else:
          error(win.w, "Unable to write to file")

proc undo(menuItem: PMenuItem, user_data: pgpointer) = 
  var current = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[current].buffer.canUndo():
    win.Tabs[current].buffer.undo()
  
proc redo(menuItem: PMenuItem, user_data: pgpointer) =
  var current = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[current].buffer.canRedo():
    win.Tabs[current].buffer.redo()
    
proc find_Activate(menuItem: PMenuItem, user_data: pgpointer) = 
  win.findBar.show()
  win.replaceEntry.hide()
  win.replaceLabel.hide()
  win.replaceBtn.hide()
  win.replaceAllBtn.hide()

proc replace_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  win.findBar.show()
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
  pegLineWarning = peg"{[^(]*} '(' {\d+} ', ' \d+ ') ' 'Warning:'/'Hint:' \s* {.*}"
  pegOtherError = peg"'Error:' \s* {.*}"
  pegSuccess = peg"'Hint: operation successful'.*"
  pegOfInterest = pegLineError / pegLineWarning / pegOtherError / pegSuccess

proc CompileRun_Activate(menuitem: PMenuItem, user_data: pgpointer) =
  saveFile(nil, nil)
  var currentTab = win.SourceViewTabs.getCurrentPage()
  if win.Tabs[currentTab].filename != "":
    # Clear the outputTextView
    win.outputTextView.getBuffer().setText("", 0)
    
    # TODO: Make the compile & run command customizable(put in the settings)
    # Compile
    var a = parseCmdLine("c \"$1\"" % [win.Tabs[currentTab].filename])
    var p = startProcess(command="nimrod", args=a,
                      options={poStdErrToStdOut, poUseShell})
    var outp = p.outputStream
    
    # Colors
    var normalTag = win.outputTextView.getBuffer().createTag(
            "normalTag", "foreground", "#3d3d3d", nil)
    var errorTag = win.outputTextView.getBuffer().createTag(
            "errorTag", "foreground", "red", nil)
    var warningTag = win.outputTextView.getBuffer().createTag(
            "warningTag", "foreground", "darkorange", nil)
    var successTag = win.outputTextView.getBuffer().createTag(
            "successTag", "foreground", "darkgreen", nil)

    var iter: TTextIter
    while running(p) or not outp.atEnd(outp):
      var x = outp.readLine()
      if x =~ pegLineError / pegOtherError:
        win.outputTextView.getBuffer().getEndIter(addr(iter))
        x.add("\n")
        win.outputTextView.getBuffer().insertWithTags(addr(iter), x, len(x), errorTag)
      elif x=~ pegSuccess:
        win.outputTextView.getBuffer().getEndIter(addr(iter))
        x.add("\n")
        win.outputTextView.getBuffer().insertWithTags(addr(iter), x, len(x), successTag)
        
        # Launch the process
        var filename = win.Tabs[currentTab].filename
        var output = "\n" & osProc.execProcess(splitFile(filename).dir /
              splitFile(filename).name & ".exe")
        win.outputTextView.getBuffer().getEndIter(addr(iter))
        win.outputTextView.getBuffer().insert(addr(iter), output, len(output))
        
      elif x =~ pegLineWarning:
        win.outputTextView.getBuffer().getEndIter(addr(iter))
        x.add("\n")
        win.outputTextView.getBuffer().insertWithTags(addr(iter), x, len(x), warningTag)
      else:
        win.outputTextView.getBuffer().getEndIter(addr(iter))
        x.add("\n")
        win.outputTextView.getBuffer().insertWithTags(addr(iter), x, len(x), normalTag)
    
    # Show the bottomPanelTabs
    if not win.settings.bottomPanelVisible:
      win.bottomPanelTabs.show()
      win.settings.bottomPanelVisible = true
  
  
# -- FindBar

proc findText(forward: bool) =
  # This proc get's called when the 'Next' or 'Prev' buttons
  # are pressed, forward is a boolean which is
  # True for Next and False for Previous
  
  var text = getText(win.findEntry)

  # TODO: regex, pegs, style insensitive searching

  # Get the current tab
  var currentTab = win.SourceViewTabs.getCurrentPage()
  
  # Get the position where the cursor is
  # Search based on that
  var startSel, endSel: TTextIter
  discard win.Tabs[currentTab].buffer.getSelectionBounds(
      addr(startsel), addr(endsel))
  
  var startMatch, endMatch: TTextIter
  var matchFound: gboolean
  
  var options: TTextSearchFlags
  if win.settings.search == "caseinsens":
    options = TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY or TEXT_SEARCH_CASE_INSENSITIVE
  else:
    options = TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY
  
  if forward:
    matchFound = gtksourceview.forwardSearch(addr(endSel), text, 
        options, addr(startMatch), addr(endMatch), nil)
  else:
    matchFound = gtksourceview.backwardSearch(addr(startSel), text, 
        options, addr(startMatch), addr(endMatch), nil)
  
  if matchFound:
    win.Tabs[currentTab].buffer.moveMarkByName("insert", addr(startMatch))
    win.Tabs[currentTab].buffer.moveMarkByName("selection_bound", addr(endMatch))
    discard PTextView(win.Tabs[currentTab].sourceView).
        scrollToIter(addr(startMatch), 0.0, True, 0.5, 0.5)

proc nextBtn_Clicked(button: PButton, user_data: pgpointer) = findText(True)
proc prevBtn_Clicked(button: PButton, user_data: pgpointer) = findText(False)
proc replaceBtn_Clicked(button: PButton, user_data: pgpointer) =
  #
proc replaceAllBtn_Clicked(button: PButton, user_data: pgpointer) =
  #

proc closeBtn_Clicked(button: PButton, user_data: pgpointer) = win.findBar.hide()

proc caseSens_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer){.cdecl.} =
  win.settings.search = "casesens"
proc caseInSens_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer){.cdecl.} =
  win.settings.search = "caseinsens"
proc style_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer){.cdecl.} =
  win.settings.search = "style"
proc regex_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer){.cdecl.} =
  win.settings.search = "regex"
proc peg_Changed(radiomenuitem: PRadioMenuitem, user_data: pgpointer){.cdecl.} =
  win.settings.search = "peg"

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
  of "casesens":
    PCheckMenuItem(caseSensMenuItem).ItemSetActive(True)
  of "caseinsens":
    PCheckMenuItem(caseInSensMenuItem).ItemSetActive(True)
  of "style":
    PCheckMenuItem(styleMenuItem).ItemSetActive(True)
  of "regex":
    PCheckMenuItem(regexMenuItem).ItemSetActive(True)
  of "peg":
    PCheckMenuItem(pegMenuItem).ItemSetActive(True)

  extraMenu.popup(nil, nil, nil, nil, 0, get_current_event_time())


# GUI Initialization

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

  var sep1 = separator_menu_item_new()
  FileMenu.append(sep1)
  sep1.show()

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
                          SIGNAL_FUNC(saveFile), nil)

  var SaveAsMenuItem = menu_item_new("Save As...") # Save as...
  # CTRL + Shift + S no idea how to do this :(
  SaveMenuItem.add_accelerator("activate", accGroup, 
                  KEY_s, CONTROL_MASK or gdk2.SHIFT_MASK, ACCEL_VISIBLE) 
  FileMenu.append(SaveAsMenuItem)
  show(SaveAsMenuItem)
  #discard signal_connect(SaveAsMenuItem, "activate", 
  #                        SIGNAL_FUNC(FileSaveClicked), nil)
  
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

  var editSep = separator_menu_item_new()
  EditMenu.append(editSep)
  editSep.show()
  
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

  var editSep1 = separator_menu_item_new()
  EditMenu.append(editSep1)
  editSep1.show()
  
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
  
  var BottomPanelMenuItem = check_menu_item_new("Bottom Panel") # Bottom Panel
  PCheckMenuItem(BottomPanelMenuItem).itemSetActive(win.settings.bottomPanelVisible)
  BottomPanelMenuItem.add_accelerator("activate", accGroup, 
                  KEY_f9, CONTROL_MASK, ACCEL_VISIBLE) 
  ViewMenu.append(BottomPanelMenuItem)
  show(BottomPanelMenuItem)
  discard signal_connect(BottomPanelMenuItem, "toggled", 
                          SIGNAL_FUNC(aporia.viewBottomPanel_Toggled), nil)
  
  var ViewMenuItem = menuItemNewWithMnemonic("_View")

  ViewMenuItem.setSubMenu(ViewMenu)
  ViewMenuItem.show()
  TopMenu.append(ViewMenuItem)       
  
  
  # Tools menu
  var ToolsMenu = menuNew()
  
  var CompileRunMenuItem = menu_item_new("Compile and Run") # compile and run
  CompileRunMenuItem.add_accelerator("activate", accGroup, 
                  KEY_f5, 0, ACCEL_VISIBLE) 
  ToolsMenu.append(CompileRunMenuItem)
  show(CompileRunMenuItem)
  discard signal_connect(CompileRunMenuItem, "activate", 
                          SIGNAL_FUNC(aporia.CompileRun_Activate), nil)
  
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
                      "Save", SIGNAL_FUNC(saveFile), nil, -1)
  TopBar.appendSpace()
  var UndoItem = TopBar.insertStock(STOCK_UNDO, "Undo", 
                      "Undo", SIGNAL_FUNC(aporia.undo), nil, -1)
  var RedoItem = TopBar.insertStock(STOCK_REDO, "Redo",
                      "Redo", SIGNAL_FUNC(aporia.redo), nil, -1)
  
  MainBox.packStart(TopBar, False, False, 0)
  TopBar.show()
  
proc initSourceViewTabs() =
  win.SourceViewTabs = notebookNew()
  win.SourceViewTabs.set_scrollable(True)
  
  win.SourceViewTabs.show()
  if lastSession.len() != 0:
    for i in items(lastSession):
      addTab("", i.split('|')[0])
      
      var iter: TTextIter
      win.Tabs[win.Tabs.len()-1].buffer.getIterAtOffset(addr(iter),
          i.split('|')[1].parseInt())
      win.Tabs[win.Tabs.len()-1].buffer.moveMarkByName("insert",
          addr(iter))
      win.Tabs[win.Tabs.len()-1].buffer.moveMarkByName("selection_bound",
            addr(iter))
      var currentTab = win.SourceViewTabs.getCurrentPage()

      # TODO: Fix this..... :(
      discard PTextView(win.Tabs[currentTab].sourceView).
          scrollToIter(addr(iter), 0.0, True, 0.5, 0.5)
      
  else:
    addTab("", "")
  
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
  
  outputTab.show()

proc initTAndBP(MainBox: PBox) =
  # This init's the HPaned, which splits the sourceViewTabs
  # and the BottomPanelTabs
  
  initSourceViewTabs()
  initBottomTabs()
  
  var TAndBPVPaned = vpanedNew()
  # yay @ named arguments :D
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
  discard win.findEntry.signalConnect("activate", SIGNAL_FUNC(aporia.nextBtn_Clicked), nil)
  win.findEntry.show()
  var rq: TRequisition 
  win.findEntry.sizeRequest(addr(rq))

  # Make the (find) text entry longer
  win.findEntry.set_size_request(190, rq.height)
  
  # Add a Label 'Replace' 
  # - This Is only shown, when the 'Search & Replace'(CTRL + H) is shown
  win.replaceLabel = labelNew("Replace:")
  win.findBar.packStart(win.replaceLabel, False, False, 0)
  #replaceLabel.show()
  
  # Add a (replace) text entry 
  # - This Is only shown, when the 'Search & Replace'(CTRL + H) is shown
  win.replaceEntry = entryNew()
  win.findBar.packStart(win.replaceEntry, False, False, 0)
  #win.replaceEntry.show()
  var rq1: TRequisition 
  win.replaceEntry.sizeRequest(addr(rq1))

  # Make the (replace) text entry longer
  win.replaceEntry.set_size_request(100, rq1.height)
  
  # Find next button
  var nextBtn = buttonNew("Next")
  win.findBar.packStart(nextBtn, false, false, 0)
  discard nextBtn.signalConnect("clicked", SIGNAL_FUNC(aporia.nextBtn_Clicked), nil)
  nextBtn.show()
  var nxtBtnRq: TRequisition
  nextBtn.sizeRequest(addr(nxtBtnRq))
  
  # Find previous button
  var prevBtn = buttonNew("Previous")
  win.findBar.packStart(prevBtn, false, false, 0)
  discard prevBtn.signalConnect("clicked", SIGNAL_FUNC(aporia.prevBtn_Clicked), nil)
  prevBtn.show()
  
  # Replace button
  # - This Is only shown, when the 'Search & Replace'(CTRL + H) is shown
  win.replaceBtn = buttonNew("Replace")
  win.findBar.packStart(win.replaceBtn, false, false, 0)
  discard win.replaceBtn.signalConnect("clicked", SIGNAL_FUNC(aporia.replaceBtn_Clicked), nil)
  #replaceBtn.show()

  # Replace all button
  # - this Is only shown, when the 'Search & Replace'(CTRL + H) is shown
  win.replaceAllBtn = buttonNew("Replace All")
  win.findBar.packStart(win.replaceAllBtn, false, false, 0)
  discard win.replaceAllBtn.signalConnect("clicked", SIGNAL_FUNC(aporia.replaceAllBtn_Clicked), nil)
  #replaceAllBtn.show()
  
  # Right side ...
  
  # Close button - With a close stock image
  var closeBtn = buttonNew()
  var closeImage = imageNewFromStock(STOCK_CLOSE, ICON_SIZE_SMALL_TOOLBAR)
  var closeBox = hboxNew(False, 0)
  closeBtn.add(closeBox)
  closeBox.show()
  closeBox.add(closeImage)
  closeImage.show()
  discard closeBtn.signalConnect("clicked", SIGNAL_FUNC(aporia.closeBtn_Clicked), nil)
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
  discard extraBtn.signalConnect("clicked", SIGNAL_FUNC(aporia.extraBtn_Clicked), nil)
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
  var LangMan = languageManagerGetDefault()
  var nimLang = LangMan.getLanguage("nimrod")
  win.nimLang = nimLang
  
  # Load the scheme
  var schemeMan = schemeManagerGetDefault()
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
  discard win.w.signalConnect("window-state-event", SIGNAL_FUNC(aporia.windowState_Changed), nil)
  
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
    dialogs.warning(win.w, "Error parsing the configuration file, using default settings.")
  
  
nimrod_init()
initControls()
main()
