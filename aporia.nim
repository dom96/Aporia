#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2010 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import glib2, gtk2, gdk2, gtksourceview, dialogs, os, pango
import settings, types
{.push callConv:cdecl.}

var win: types.MainWin
win.Tabs = @[]
# Some default settings - These will be loaded from a cfg file in the future
win.settings.search = "caseinsens"
win.settings.font = "monospace 9"
win.settings.colorSchemeID = "cobalt"

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
      name = "Untitled *"
    else:
      win.Tabs[current].saved = False
      name = splitFile(win.Tabs[current].filename).name &
                      splitFile(win.Tabs[current].filename).ext & " *"
    
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
  SourceView = sourceViewNew()
  PSourceView(SourceView).setInsertSpacesInsteadOfTabs(True)
  PSourceView(SourceView).setIndentWidth(2)
  PSourceView(SourceView).setShowLineNumbers(True)

  var font = font_description_from_string(win.settings.font)
  SourceView.modifyFont(font)
  
  scrollWindow.add(SourceView)
  SourceView.show()
  # -- Set the syntax highlighter language
  buffer = PSourceBuffer(PTextView(SourceView).getBuffer())
  
  # UGLY workaround for yet another compiler bug:
  discard gsignalConnect(buffer, "mark-set", 
                         GCallback(aporia.cursorMoved), nil)
  discard gsignalConnect(buffer, "changed", GCallback(aporia.changed), nil)

  buffer.setLanguage(win.nimLang)
  buffer.setScheme(win.scheme)

proc addTab(name: string, filename: string) =
  var nam = name
  if nam == "": nam = "Untitled"
  if filename == "": nam.add(" *")
  elif filename != "" and name == "":
    # Get the name.ext of the filename, for the tabs title
    nam = splitFile(filename).name & splitFile(filename).ext

  # Init the sourceview
  var sourceView: PWidget
  var scrollWindow: PScrolledWindow
  var buffer: PSourceBuffer
  initSourceView(sourceView, scrollWindow, buffer)
  
  var TabLabel = createTabLabel(nam, scrollWindow)
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
  
# -- FindBar

proc findText(forward: bool) =
  # This proc get's called when the 'Next' or 'Prev' buttons
  # are pressed, user_data is a boolean which is
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
  
  # Tools menu
  
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
  win.w.setDefaultSize(800, 600)
  win.w.setTitle("Aporia IDE")
  discard win.w.signalConnect("destroy", SIGNAL_FUNC(aporia.destroy), nil)
  
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
