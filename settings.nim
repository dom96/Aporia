#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2010 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, gdk2, glib2, pango, os
import gtksourceview, types

{.push callConv:cdecl.}

const
  langSpecs* = "share/gtksourceview-2.0/language-specs"
  styles* = "share/gtksourceview-2.0/styles"

var win: ptr types.MainWin

# -- Fonts and Colors --

proc addSchemes(schemeTree: PTreeView, schemeModel: PListStore) =
  var schemeMan = schemeManagerGetDefault()
  var schemepaths: array[0..1, cstring] =
          [cstring(os.getApplicationDir() / styles), nil]
  schemeMan.setSearchPath(addr(schemepaths))
  var schemes = cstringArrayToSeq(schemeMan.getSchemeIds())
  for i in countdown(schemes.len() - 1, 0):
    var iter: TTreeIter
    # Add a new TreeIter to the treeview
    schemeModel.append(addr(iter))
    # Get the scheme name and decription
    var scheme = schemeMan.getScheme(schemes[i])
    var name = $scheme.getName()
    var desc = $scheme.getDescription()
    # Set the TreeIter's values
    schemeModel.set(addr(iter), 0, schemes[i], 1, "<b>" & name & "</b> - " &
        desc, -1)

    if schemes[i] == win.settings.colorSchemeID:
      schemeTree.getSelection.selectIter(addr(iter))

proc schemesTreeView_onChanged(selection: PGObject, user_data: pgpointer) =
  var iter: TTreeIter
  var model: PTreeModel
  var value: cstring
  
  if getSelected(PTreeSelection(selection), addr(model), addr(iter)):
    model.get(addr(iter), 0, addr(value), -1)
    win.settings.colorSchemeID = $value

    var schemeMan = schemeManagerGetDefault()
    var schemepaths: array[0..1, cstring] =
            [cstring(os.getApplicationDir() / styles), nil]
    schemeMan.setSearchPath(addr(schemepaths))
    win.scheme = schemeMan.getScheme(value)
    # Loop through each tab, and set the scheme
    for i in items(win.Tabs):
      i.buffer.setScheme(win.scheme)
      
proc fontDialog_OK(widget: PWidget, user_data: PFontSelectionDialog) =
  PDialog(userData).response(RESPONSE_OK)
  
proc fontDialog_Canc(widget: PWidget, user_data: PFontSelectionDialog) =
  PDialog(userData).response(RESPONSE_CANCEL)

proc fontChangeBtn_Clicked(widget: PWidget, user_data: PEntry) =
  # Initialize the FontDialog
  var fontDialog = fontSelectionDialogNew("Select font")
  fontDialog.setTransientFor(win.w)
  discard fontDialog.dialogSetFontName(win.settings.font)
  
  discard fontDialog.okButton.GSignalConnect("clicked", 
      G_CALLBACK(fontDialog_OK), fontDialog)
  discard fontDialog.cancelButton.GSignalConnect("clicked", 
      G_CALLBACK(fontDialog_Canc), fontDialog)
  
  # This will wait until the user responds(clicks the OK or Cancel button)
  var result = fontDialog.run()
  # If the response, is OK, then change the font.
  if result == RESPONSE_OK:
    win.settings.font = $fontDialog.dialogGetFontName()
    userData.setText(fontDialog.dialogGetFontName())
    # Loop through each tab, and change the font
    for i in items(win.Tabs):
      var font = fontDescriptionFromString(win.settings.font)
      i.sourceView.modifyFont(font)
    
  gtk2.POBject(fontDialog).destroy()

proc addTextEdit(parent: PVBox, labelText, value: string): PEntry = 
  var label = labelNew("")
  label.setMarkup("<b>" & labelText & "</b>")
  
  var HBox = hboxNew(false, 0)
  parent.packStart(HBox, false, false, 0)
  HBox.show()
  
  HBox.packStart(Label, false, false, 5)
  Label.show()
  
  var EntryHBox = hboxNew(false, 0)
  parent.packStart(EntryHBox, false, false, 0)
  EntryHBox.show()
  
  var entry = entryNew()
  entry.setEditable(True)
  entry.setText(value)
  entryHBox.packStart(entry, false, false, 20)
  entry.show()
  result = entry

var
  nimrodEdit, custom1Edit, custom2Edit, custom3Edit: PEntry

proc initTools(settingsTabs: PNotebook) =
  var t = vboxNew(false, 5)
  discard settingsTabs.appendPage(t, labelNew("Tools"))
  t.show()
  
  nimrodEdit = addTextEdit(t, "Nimrod", win.settings.nimrodCmd)
  custom1Edit = addTextEdit(t, "Custom Command 1", win.settings.customCmd1)
  custom2Edit = addTextEdit(t, "Custom Command 2", win.settings.customCmd2)
  custom3Edit = addTextEdit(t, "Custom Command 3", win.settings.customCmd3)


proc initFontsColors(settingsTabs: PNotebook) =
  var fontsColorsLabel = labelNew("Fonts and colors")
  var fontsColorsVBox = vboxNew(False, 5)
  discard settingsTabs.appendPage(fontsColorsVBox, fontsColorsLabel)
  fontsColorsVBox.show()
  
  # 'Font' label
  var fontLabelHBox = hboxNew(False, 0)
  fontsColorsVBox.packStart(fontLabelHBox, False, False, 0)
  fontLabelHBox.show()
  
  var fontLabel = labelNew("")
  fontLabel.setMarkup("<b>Font</b>")
  fontLabelHBox.packStart(fontLabel, False, False, 5)
  fontLabel.show()
  
  # Entry (For the font name and size, for example 'monospace 9')
  var fontEntryHBox = hboxNew(False, 0)
  fontsColorsVBox.packStart(fontEntryHBox, False, False, 0)
  fontEntryHBox.show()
  
  var fontEntry = entryNew()
  fontEntry.setEditable(False)
  fontEntry.setText(win.settings.font)
  fontEntryHBox.packStart(fontEntry, False, False, 20)
  fontEntry.show()
  
  # Change font button
  var fontChangeBtn = buttonNew("Change Font")
  discard fontChangeBtn.GSignalConnect("clicked", 
    G_CALLBACK(fontChangeBtn_Clicked), fontEntry)
  fontEntryHBox.packEnd(fontChangeBtn, False, False, 10)
  fontChangeBtn.show()

  # 'Color Scheme' label
  var schemeLabelHBox = hboxNew(False, 0)
  fontsColorsVBox.packStart(schemeLabelHBox, False, False, 0)
  schemeLabelHBox.show()
  
  var schemeLabel = labelNew("")
  schemeLabel.setMarkup("<b>Color Scheme</b>")
  schemeLabelHBox.packStart(schemeLabel, False, False, 5)
  schemeLabel.show()
  
  # Scheme TreeView(Well ListView...)
  var schemeTreeHBox = hboxNew(False, 0)
  fontsColorsVBox.packStart(schemeTreeHBox, True, True, 10)
  schemeTreeHBox.show()
  
  var schemeTree = treeviewNew()
  schemeTree.setHeadersVisible(False) #Make the headers invisible
  var selection = schemeTree.getSelection()
  discard selection.GSignalConnect("changed", 
    G_CALLBACK(schemesTreeView_onChanged), nil)
  var schemeTreeScrolled = scrolledWindowNew(nil, nil)
  # Make the scrollbars invisible by default
  schemeTreeScrolled.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  # Add a border
  schemeTreeScrolled.setShadowType(SHADOW_IN)
  schemeTreeScrolled.add(schemeTree)
  schemeTreeHBox.packStart(schemeTreeScrolled, True, True, 20)
  schemeTreeScrolled.show()
  
  var schemeModel = listStoreNew(2, TYPE_STRING, TYPE_STRING)
  schemeTree.setModel(schemeModel)
  schemeTree.show()
  
  var renderer = cellRendererTextNew()
  var column = treeViewColumnNewWithAttributes("Schemes", 
                                               renderer, "markup", 1, nil)
  discard schemeTree.appendColumn(column)
  # Add all the schemes available, to the TreeView
  schemeTree.addSchemes(schemeModel)

# -- Editor settings
proc showLineNums_Toggled(button: PToggleButton, user_data: pgpointer) =
  win.settings.showLineNumbers = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    PSourceView(i.sourceView).setShowLineNumbers(win.settings.showLineNumbers)
    
proc hlCurrLine_Toggled(button: PToggleButton, user_data: pgpointer) =
  win.settings.highlightCurrentLine = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    PSourceView(i.sourceView).setHighlightCurrentLine(
        win.settings.highlightCurrentLine)
    
proc showMargin_Toggled(button: PToggleButton, user_data: pgpointer) =
  win.settings.rightMargin = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    PSourceView(i.sourceView).setShowRightMargin(win.settings.rightMargin)

proc brackMatch_Toggled(button: PToggleButton, user_data: pgpointer) =
  win.settings.highlightMatchingBrackets = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    i.buffer.setHighlightMatchingBrackets(
        win.settings.highlightMatchingBrackets)

proc indentWidth_changed(spinbtn: PSpinButton, user_data: pgpointer) =
  win.settings.indentWidth = int(spinbtn.getValue())
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    PSourceView(i.sourceView).setIndentWidth(win.settings.indentWidth)
  
proc autoIndent_Toggled(button: PToggleButton, user_data: pgpointer) =
  win.settings.autoIndent = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    PSourceView(i.sourceView).setAutoIndent(win.settings.autoIndent)

proc initEditor(settingsTabs: PNotebook) =
  var editorLabel = labelNew("Editor")
  var editorVBox = vboxNew(False, 5)
  discard settingsTabs.appendPage(editorVBox, editorLabel)
  editorVBox.show()
  
  # indentWidth - SpinButton
  var indentWidthHBox = hboxNew(False, 0)
  editorVBox.packStart(indentWidthHBox, False, False, 5)
  indentWidthHBox.show()
  
  var indentWidthLabel = labelNew("Indent width: ")
  indentWidthHBox.packStart(indentWidthLabel, False, False, 20)
  indentWidthLabel.show()
  
  var indentWidthSpinButton = spinButtonNew(1.0, 24.0, 1.0)
  indentWidthSpinButton.setValue(win.settings.indentWidth.toFloat())
  discard indentWidthSpinButton.GSignalConnect("value-changed", 
    G_CALLBACK(indentWidth_changed), nil)
  indentWidthHBox.packStart(indentWidthSpinButton, False, False, 0)
  indentWidthSpinButton.show()
  
  # showLineNumbers - checkbox
  var showLineNumsHBox = hboxNew(False, 0)
  editorVBox.packStart(showLineNumsHBox, False, False, 0)
  showLineNumsHBox.show()
  
  var showLineNumsCheckBox = checkButtonNew("Show line numbers")
  showLineNumsCheckBox.setActive(win.settings.showLineNumbers)
  discard showLineNumsCheckBox.GSignalConnect("toggled", 
    G_CALLBACK(showLineNums_Toggled), nil)
  showLineNumsHBox.packStart(showLineNumsCheckBox, False, False, 20)
  showLineNumsCheckBox.show()
  
  # highlightCurrentLine - checkbox
  var hlCurrLineHBox = hboxNew(False, 0)
  editorVBox.packStart(hlCurrLineHBox, False, False, 0)
  hlCurrLineHBox.show()
  
  var hlCurrLineCheckBox = checkButtonNew("Highlight selected line")
  hlCurrLineCheckBox.setActive(win.settings.highlightCurrentLine)
  discard hlCurrLineCheckBox.GSignalConnect("toggled", 
    G_CALLBACK(hlCurrLine_Toggled), nil)
  hlCurrLineHBox.packStart(hlCurrLineCheckBox, False, False, 20)
  hlCurrLineCheckBox.show()
  
  # showRightMargin - checkbox
  var showMarginHBox = hboxNew(False, 0)
  editorVBox.packStart(showMarginHBox, False, False, 0)
  showMarginHBox.show()
  
  var showMarginCheckBox = checkButtonNew("Show right margin")
  showMarginCheckBox.setActive(win.settings.rightMargin)
  discard showMarginCheckBox.GSignalConnect("toggled", 
    G_CALLBACK(showMargin_Toggled), nil)
  showMarginHBox.packStart(showMarginCheckBox, False, False, 20)
  showMarginCheckBox.show()
  
  # bracketMatching - checkbox
  var brackMatchHBox = hboxNew(False, 0)
  editorVBox.packStart(brackMatchHBox, False, False, 0)
  brackMatchHBox.show()
  
  var brackMatchCheckBox = checkButtonNew("Enable bracket matching")
  brackMatchCheckBox.setActive(win.settings.highlightMatchingBrackets)
  discard brackMatchCheckBox.GSignalConnect("toggled", 
    G_CALLBACK(brackMatch_Toggled), nil)
  brackMatchHBox.packStart(brackMatchCheckBox, False, False, 20)
  brackMatchCheckBox.show()
  
  # autoIndent - checkbox
  var autoIndentHBox = hboxNew(False, 0)
  editorVBox.packStart(autoIndentHBox, False, False, 0)
  autoIndentHBox.show()
  
  var autoIndentCheckBox = checkButtonNew("Enable auto indent")
  autoIndentCheckBox.setActive(win.settings.autoIndent)
  discard autoIndentCheckBox.GSignalConnect("toggled", 
    G_CALLBACK(autoIndent_Toggled), nil)
  autoIndentHBox.packStart(autoIndentCheckBox, False, False, 20)
  autoIndentCheckBox.show()

var
  dialog: gtk2.PWindow

proc closeDialog(widget: pWidget, user_data: pgpointer) =
  win.settings.nimrodCmd = $nimrodEdit.getText()
  win.settings.customCmd1 = $custom1Edit.getText()
  win.settings.customCmd2 = $custom2Edit.getText()
  win.settings.customCmd3 = $custom3Edit.getText()

  gtk2.PObject(dialog).destroy()

proc showSettings*(aWin: var types.MainWin) =
  win = addr(aWin)  # This has to be a pointer
                    # Because i need the settings to be changed
                    # in aporia.nim not in here.

  dialog = windowNew(gtk2.WINDOW_TOPLEVEL)
  dialog.setDefaultSize(330, 400)
  dialog.setSizeRequest(330, 400)
  dialog.setTransientFor(win.w)
  dialog.setResizable(False)
  dialog.setTitle("Settings")
  dialog.setTypeHint(WINDOW_TYPE_HINT_DIALOG)

  var contentArea = vboxNew(False, 0)
  dialog.add(contentArea)
  contentArea.show()
  
  var sHBox = hboxNew(False, 0) # Just used for some padding
  contentArea.packStart(sHBox, True, True, 10)
  sHBox.show()
  
  var tabsVBox = vboxNew(False, 0) # So that HSeperator is close to the tabs
  sHBox.packStart(tabsVBox, True, True, 10)
  tabsVBox.show()
  
  var settingsTabs = notebookNew()
  tabsVBox.packStart(settingsTabs, True, True, 0)
  settingsTabs.show()
  
  var tabsBottomLine = hSeparatorNew()
  tabsVBox.packStart(tabsBottomLine, False, False, 0)
  tabsBottomLine.show()
  
  # HBox for the close button
  var bottomHBox = hboxNew(False, 0)
  contentArea.packStart(bottomHBox, False, False, 5)
  bottomHBox.show()
  
  var closeBtn = buttonNewWithMnemonic("_Close")
  discard closeBtn.GSignalConnect("clicked", 
    G_CALLBACK(closeDialog), nil)
  bottomHBox.packEnd(closeBtn, False, False, 10)
  # Change the size of the close button
  var rq1: TRequisition 
  closeBtn.sizeRequest(addr(rq1))
  closeBtn.set_size_request(rq1.width + 10, rq1.height + 4)
  closeBtn.show()
  
  initEditor(settingsTabs)
  initFontsColors(settingsTabs)
  initTools(settingsTabs)
  
  dialog.show()
