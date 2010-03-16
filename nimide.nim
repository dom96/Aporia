#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2010 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import glib2, gtk2, gdk2, gtksourceview, dialogs, os, pango

type
  MainWin = object
    # Widgets
    w: gtk2.PWindow
    nimLang: PSourceLanguage
    SourceViewTabs: PNotebook
    bottomBar: PStatusBar
    
    findBar: PFixed
    findEntry: PEntry
    
    Tabs: seq[Tab] # Other

  Tab = object
    buffer: PSourceBuffer
    sourceView: PWidget
    saved: bool
    filename: string


var win: MainWin
win.Tabs = @[]

# GTK Events
# -- w(PWindow)
proc destroy(widget: PWidget, data: pgpointer){.cdecl.} = 
  main_quit()

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
  #echo("cursorMoved")
  updateStatusBar(buffer)

var repelChanged: bool = False  # When a file is opened, the text changes
                                # Repel the "changed" event, when opening files 

proc changed(buffer: PTextBuffer, user_data: pgpointer){.cdecl.} =
  # Update the 'Line & Column'
  updateStatusBar(buffer)

  if repelChanged == False:
    # Change the tabs state to 'unsaved'
    # and add '*' to the Tab Name
    var current = win.SourceViewTabs.getCurrentPage()
    var name = ""
    if win.Tabs[current].filename == "":
      win.Tabs[current].saved = False
      name = "Untitled * "
    else:
      win.Tabs[current].saved = False
      name = splitFile(win.Tabs[current].filename).name &
                      splitFile(win.Tabs[current].filename).ext & " *"
    win.sourceViewTabs.setTabLabelText(
        win.sourceViewTabs.getNthPage(current), name)
  
# Other(Helper) functions

proc initSourceView(SourceView: var PWidget, scrollWindow: var PScrolledWindow,
                    buffer: var PSourceBuffer) =
  # This gets called by addTab
  # Each tabs creats a new SourceView
  # SourceScrolledWindow(ScrolledWindow)
  scrollWindow = scrolledWindowNew(nil, nil)
  scrollWindow.show()
  
  # SourceView(gtkSourceView)
  SourceView = sourceViewNew()
  PSourceView(SourceView).setInsertSpacesInsteadOfTabs(True)
  PSourceView(SourceView).setIndentWidth(2)
  PSourceView(SourceView).setShowLineNumbers(True)

  var font = font_description_from_string("monospace 9")
  SourceView.modifyFont(font)
  
  scrollWindow.addWithViewport(SourceView)
  SourceView.show()
  # -- Set the syntax highlighter language
  buffer = PSourceBuffer(PTextView(SourceView).getBuffer())
  
  # UGLY workaround for yet another compiler bug:
  discard gsignalConnect(buffer, "mark-set", 
                         GCallback(nimide.cursorMoved), nil)
  discard gsignalConnect(buffer, "changed", GCallback(nimide.changed), nil)
  
  # Load up the language style
  var LangMan = languageManagerNew()
  var nimLang = LangMan.getLanguage("nimrod")
  win.nimLang = nimLang

  buffer.setLanguage(win.nimLang)

proc addTab(name: string, filename: string) =
  var nam = name
  if nam == "": nam = "Untitled"
  if filename == "": nam.add(" * ")
  elif filename != "" and name == "":
    # Get the name.ext of the filename, for the tabs title
    nam = splitFile(filename).name & splitFile(filename).ext
    

  var TabLabel = labelNew(nam)
  
  # Init the sourceview
  var sourceView: PWidget
  var scrollWindow: PScrolledWindow
  var buffer: PSourceBuffer
  initSourceView(sourceView, scrollWindow, buffer)
  
  # Add a tab
  discard win.SourceViewTabs.appendPage(scrollWindow, TabLabel)

  var nTab: Tab
  nTab.buffer = buffer
  nTab.sourceView = sourceView
  nTab.saved = False
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
    var file: string = readFile(path)
    if file != nil:
      addTab("", path)
      # Repel the 'changed' event
      repelChanged = True
      # Set the TextBuffer's text.
      win.Tabs[win.Tabs.len()-1].buffer.set_text(file, len(file))
      # Switch to the newly created tab
      win.sourceViewTabs.setCurrentPage(win.Tabs.len()-1)
      
      repelChanged = False # Change it back to default
    else:
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
          
          # Change the tab name, .Tabs.filename etc.
          win.Tabs[current].filename = path
          win.Tabs[current].saved = True
          var name = splitFile(path).name & splitFile(path).ext
          win.sourceViewTabs.setTabLabelText(
              win.sourceViewTabs.getNthPage(current), name)
          
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
    
# -- FindBar

proc findText(button: PButton, user_data: pgpointer) =
  # This proc get's called when the 'Next' or 'Prev' buttons
  # are pressed, user_data is a boolean which is
  # True for Next and False for Previous
  
  var findText = getText(win.findEntry)
  echo("text=", findText)
  # Get the current tab
  var currentTab = win.SourceViewTabs.getCurrentPage()
  
  var startFind, endFind: TTextIter
  win.Tabs[currentTab].buffer.getStartIter(addr(startFind))
  win.Tabs[currentTab].buffer.getEndIter(addr(endFind))
  
  var startMatch, endMatch: TTextIter
  var matchFound: gboolean
  
  var usrData = (cast[ptr bool](user_data))^
  echo(usrData)
  if not usrData:
    matchFound = forwardSearch(addr(startFind), findText, TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY, addr(startMatch), addr(endMatch), nil)
  else:
    matchFound = backwardSearch(addr(startFind), findText, TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY, addr(startMatch), addr(endMatch), nil)
  
  if matchFound:
    win.Tabs[currentTab].buffer.moveMarkByName("insert", addr(startMatch))
    win.Tabs[currentTab].buffer.moveMarkByName("selection_bound", addr(endMatch))


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
                          SIGNAL_FUNC(nimide.openFile), nil)
  
  var SaveMenuItem = menu_item_new("Save") # Save
  # CTRL + S
  SaveMenuItem.add_accelerator("activate", accGroup, 
                  KEY_s, CONTROL_MASK, ACCEL_VISIBLE) 
  FileMenu.append(SaveMenuItem)
  show(SaveMenuItem)
  discard signal_connect(SaveMenuItem, "activate", 
                          SIGNAL_FUNC(saveFile), nil)

  var SaveAsMenuItem = menu_item_new("Save As...") # Save as...
  # CTRL + Shift + S no idea how to do this
  #SaveMenuItem.add_accelerator("activate", accGroup, 
  #                KEY_s, MOD1_MASK, ACCEL_VISIBLE) 
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
                          SIGNAL_FUNC(nimide.undo), nil)
  
  var RedoMenuItem = menu_item_new("Redo") # Undo
  EditMenu.append(RedoMenuItem)
  show(RedoMenuItem)
  discard signal_connect(RedoMenuItem, "activate", 
                          SIGNAL_FUNC(nimide.redo), nil)
  
  var EditMenuItem = menuItemNewWithMnemonic("_Edit")

  EditMenuItem.setSubMenu(EditMenu)
  EditMenuItem.show()
  TopMenu.append(EditMenuItem)                        
  
  # View menu
  
  # Tools menu
  
  # Help menu
  
  MainBox.packStart(TopMenu, False, False, 0)
  TopMenu.show()

proc initToolBar(MainBox: PBox) =
  # TopBar(ToolBar)
  var TopBar = toolbarNew()
  TopBar.setStyle(TOOLBAR_ICONS)
  
  var NewFileItem = TopBar.insertStock(STOCK_NEW, "New File",
                      "New File", SIGNAL_FUNC(nimide.newFile), nil, 0)
  TopBar.appendSpace()
  var OpenItem = TopBar.insertStock(STOCK_OPEN, "Open",
                      "Open", SIGNAL_FUNC(nimide.openFile), nil, -1)
  var SaveItem = TopBar.insertStock(STOCK_SAVE, "Save",
                      "Save", SIGNAL_FUNC(saveFile), nil, -1)
  TopBar.appendSpace()
  var UndoItem = TopBar.insertStock(STOCK_UNDO, "Undo", 
                      "Undo", SIGNAL_FUNC(nimide.undo), nil, -1)
  var RedoItem = TopBar.insertStock(STOCK_REDO, "Redo",
                      "Redo", SIGNAL_FUNC(nimide.redo), nil, -1)
  
  MainBox.packStart(TopBar, False, False, 0)
  TopBar.show()
  
proc initTabs(MainBox: PBox) =
  win.SourceViewTabs = notebookNew()
  win.SourceViewTabs.set_scrollable(True)
  
  MainBox.packStart(win.SourceViewTabs, True, True, 0)
  win.SourceViewTabs.show()
  addTab("", "")
  addTab("", "")
  addTab("", "")
  addTab("", "")
  
proc initFindBar(MainBox: PBox) =
  # Create a fixed container
  win.findBar = fixedNew()

  # Add a text entry
  win.findEntry = entryNew()
  win.findBar.Put(win.findEntry, 5, 0)
  win.findEntry.show()
  var rq: TRequisition 
  win.findEntry.sizeRequest(addr(rq))

  # Make the text entry longer
  win.findEntry.set_size_request(190, rq.height)
  
  var nextBtn = buttonNew("Next")
  win.findBar.Put(nextBtn, 200, 0)
  var dummyBool = True
  discard nextBtn.signalConnect("clicked", SIGNAL_FUNC(nimide.findText), addr(dummyBool))
  nextBtn.show()
  var nxtBtnRq: TRequisition
  nextBtn.sizeRequest(addr(nxtBtnRq))
  
  var prevBtn = buttonNew("Prev")
  win.findBar.Put(prevBtn, 205 + nxtBtnRq.width, 0)
  prevBtn.show()
  
  MainBox.packStart(win.findBar, False, False, 0)
  win.findBar.show()

proc initStatusBar(MainBox: PBox) =
  win.bottomBar = statusbarNew()
  MainBox.packStart(win.bottomBar, False, False, 0)
  win.bottomBar.show()
  
  discard win.bottomBar.push(0, "Line: 0 Column: 0")
  
proc initControls() =
  # Window
  win.w = windowNew(gtk2.WINDOW_TOPLEVEL)
  win.w.setDefaultSize(800, 600)
  win.w.setTitle("Aporia IDE")
  discard win.w.signalConnect("destroy", SIGNAL_FUNC(nimide.destroy), nil)
  
  # MainBox (vbox)
  var MainBox = vboxNew(False, 0)
  win.w.add(MainBox)
  
  initTopMenu(MainBox)
  
  initToolBar(MainBox)
  
  initTabs(MainBox)
  
  initFindBar(MainBox)
  
  initStatusBar(MainBox)
  
  MainBox.show()
  win.w.show()
  
  
  
nimrod_init()
initControls()
main()
