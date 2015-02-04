#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, gdk2, glib2, pango, os
import gtksourceview, utils

{.push callConv:cdecl.}

const
  langSpecs* = "share/gtksourceview-2.0/language-specs"
  styles* = "share/gtksourceview-2.0/styles"

var win: ptr utils.MainWin

# -- Fonts and Colors --

proc escapeMarkup(s: string): string =
  result = ""
  var i = 0
  while true:
    case s[i]
    of '&': result.add("&amp;")
    of '<': result.add("&lt;")
    of '>': result.add("&gt;")
    of '\0': break
    else: result.add(s[i])
    inc(i)

proc addSchemes(schemeTree: PTreeView, schemeModel: PListStore) =
  var schemeMan = schemeManagerGetDefault()
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
    schemeModel.set(addr(iter), 0, schemes[i], 1, "<b>" & escapeMarkup(name) &
                    "</b> - " & escapeMarkup(desc), -1)

    if schemes[i] == win.globalSettings.colorSchemeID:
      schemeTree.getSelection.selectIter(addr(iter))

proc schemesTreeView_onChanged(selection: PGObject, user_data: PGpointer) =
  var iter: TTreeIter
  var model: PTreeModel
  var value: cstring
  
  if getSelected(PTreeSelection(selection), addr(model), addr(iter)):
    model.get(addr(iter), 0, addr(value), -1)
    win.globalSettings.colorSchemeID = $value

    var schemeMan = schemeManagerGetDefault()
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
  discard fontDialog.dialogSetFontName(win.globalSettings.font)
  
  discard fontDialog.okButton.gsignalConnect("clicked", 
      G_CALLBACK(fontDialog_OK), fontDialog)
  discard fontDialog.cancelButton.gsignalConnect("clicked", 
      G_CALLBACK(fontDialog_Canc), fontDialog)
  
  # This will wait until the user responds(clicks the OK or Cancel button)
  var result = fontDialog.run()
  # If the response, is OK, then change the font.
  if result == RESPONSE_OK:
    win.globalSettings.font = $fontDialog.dialogGetFontName()
    userData.setText(fontDialog.dialogGetFontName())
    # Loop through each tab, and change the font
    for i in items(win.Tabs):
      var font = fontDescriptionFromString(win.globalSettings.font)
      i.sourceView.modifyFont(font)
    
  gtk2.POBject(fontDialog).destroy()

proc addTextEdit(parent: PVBox, labelText, value: string): PEntry = 
  var label = labelNew("")
  label.setMarkup("<b>" & labelText & "</b>")
  
  var HBox = hboxNew(false, 0)
  parent.packStart(HBox, false, false, 0)
  HBox.show()
  
  HBox.packStart(label, false, false, 5)
  label.show()
  
  var entryHBox = hboxNew(false, 0)
  parent.packStart(entryHBox, false, false, 0)
  entryHBox.show()
  
  var entry = entryNew()
  entry.setEditable(true)
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
  
  nimrodEdit = addTextEdit(t, "Nimrod", win.globalSettings.nimrodCmd)
  custom1Edit = addTextEdit(t, "Custom Command 1", win.globalSettings.customCmd1)
  custom2Edit = addTextEdit(t, "Custom Command 2", win.globalSettings.customCmd2)
  custom3Edit = addTextEdit(t, "Custom Command 3", win.globalSettings.customCmd3)


proc initFontsColors(settingsTabs: PNotebook) =
  var fontsColorsLabel = labelNew("Fonts and colors")
  var fontsColorsVBox = vboxNew(false, 5)
  discard settingsTabs.appendPage(fontsColorsVBox, fontsColorsLabel)
  fontsColorsVBox.show()
  
  # 'Font' label
  var fontLabelHBox = hboxNew(false, 0)
  fontsColorsVBox.packStart(fontLabelHBox, false, false, 0)
  fontLabelHBox.show()
  
  var fontLabel = labelNew("")
  fontLabel.setMarkup("<b>Font</b>")
  fontLabelHBox.packStart(fontLabel, false, false, 5)
  fontLabel.show()
  
  # Entry (For the font name and size, for example 'monospace 9')
  var fontEntryHBox = hboxNew(false, 0)
  fontsColorsVBox.packStart(fontEntryHBox, false, false, 0)
  fontEntryHBox.show()
  
  var fontEntry = entryNew()
  fontEntry.setEditable(false)
  fontEntry.setText(win.globalSettings.font)
  fontEntryHBox.packStart(fontEntry, false, false, 20)
  fontEntry.show()
  
  # Change font button
  var fontChangeBtn = buttonNew("Change Font")
  discard fontChangeBtn.gsignalConnect("clicked", 
    G_CALLBACK(fontChangeBtn_Clicked), fontEntry)
  fontEntryHBox.packEnd(fontChangeBtn, false, false, 10)
  fontChangeBtn.show()

  # 'Color Scheme' label
  var schemeLabelHBox = hboxNew(false, 0)
  fontsColorsVBox.packStart(schemeLabelHBox, false, false, 0)
  schemeLabelHBox.show()
  
  var schemeLabel = labelNew("")
  schemeLabel.setMarkup("<b>Color Scheme</b>")
  schemeLabelHBox.packStart(schemeLabel, false, false, 5)
  schemeLabel.show()
  
  # Scheme TreeView(Well ListView...)
  var schemeTreeHBox = hboxNew(false, 0)
  fontsColorsVBox.packStart(schemeTreeHBox, true, true, 10)
  schemeTreeHBox.show()
  
  var schemeTree = treeviewNew()
  schemeTree.setHeadersVisible(false) # Make the headers invisible
  var selection = schemeTree.getSelection()
  discard selection.gsignalConnect("changed", 
    G_CALLBACK(schemesTreeView_onChanged), nil)
  var schemeTreeScrolled = scrolledWindowNew(nil, nil)
  # Make the scrollbars invisible by default
  schemeTreeScrolled.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  # Add a border
  schemeTreeScrolled.setShadowType(SHADOW_IN)
  
  schemeTreeScrolled.add(schemeTree)
  schemeTreeHBox.packStart(schemeTreeScrolled, true, true, 20)
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
proc showLineNums_Toggled(button: PToggleButton, user_data: PGpointer) =
  win.globalSettings.showLineNumbers = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    i.sourceView.setShowLineNumbers(win.globalSettings.showLineNumbers)
    
proc hlCurrLine_Toggled(button: PToggleButton, user_data: PGpointer) =
  win.globalSettings.highlightCurrentLine = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    i.sourceView.setHighlightCurrentLine(
        win.globalSettings.highlightCurrentLine)
    
proc showMargin_Toggled(button: PToggleButton, user_data: PGpointer) =
  win.globalSettings.rightMargin = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    i.sourceView.setShowRightMargin(win.globalSettings.rightMargin)

proc brackMatch_Toggled(button: PToggleButton, user_data: PGpointer) =
  win.globalSettings.highlightMatchingBrackets = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    i.buffer.setHighlightMatchingBrackets(
        win.globalSettings.highlightMatchingBrackets)

proc indentWidth_changed(spinbtn: PSpinButton, user_data: PGpointer) =
  win.globalSettings.indentWidth = int32(spinbtn.getValue())
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    i.sourceView.setIndentWidth(win.globalSettings.indentWidth)
  
proc autoIndent_Toggled(button: PToggleButton, user_data: PGpointer) =
  win.globalSettings.autoIndent = button.getActive()
  # Loop through each tab, and change the setting.
  for i in items(win.Tabs):
    i.sourceView.setAutoIndent(win.globalSettings.autoIndent)

proc suggestFeature_Toggled(button: PToggleButton, user_data: PGpointer) =
  win.globalSettings.suggestFeature = button.getActive()

proc showCloseOnAllTabs_Toggled(button: PToggleButton, user_data: PGpointer) =
  win.globalSettings.showCloseOnAllTabs = button.getActive()
  # Loop through each tab, and change the setting.
  for i in 0..len(win.Tabs)-1:
    if win.globalSettings.showCloseOnAllTabs:
      win.Tabs[i].closeBtn.show()
    else:
      if i == win.SourceViewTabs.getCurrentPage():
        win.Tabs[i].closeBtn.show()
      else:
        win.Tabs[i].closeBtn.hide()

proc initEditor(settingsTabs: PNotebook) =
  var editorLabel = labelNew("Editor")
  var editorVBox = vboxNew(false, 5)
  discard settingsTabs.appendPage(editorVBox, editorLabel)
  editorVBox.show()
  
  # indentWidth - SpinButton
  var indentWidthHBox = hboxNew(false, 0)
  editorVBox.packStart(indentWidthHBox, false, false, 5)
  indentWidthHBox.show()
  
  var indentWidthLabel = labelNew("Indent width: ")
  indentWidthHBox.packStart(indentWidthLabel, false, false, 20)
  indentWidthLabel.show()
  
  var indentWidthSpinButton = spinButtonNew(1.0, 24.0, 1.0)
  indentWidthSpinButton.setValue(win.globalSettings.indentWidth.toFloat())
  discard indentWidthSpinButton.gsignalConnect("value-changed", 
    G_CALLBACK(indentWidth_changed), nil)
  indentWidthHBox.packStart(indentWidthSpinButton, false, false, 0)
  indentWidthSpinButton.show()
  
  # showLineNumbers - checkbox
  var showLineNumsHBox = hboxNew(false, 0)
  editorVBox.packStart(showLineNumsHBox, false, false, 0)
  showLineNumsHBox.show()
  
  var showLineNumsCheckBox = checkButtonNew("Show line numbers")
  showLineNumsCheckBox.setActive(win.globalSettings.showLineNumbers)
  discard showLineNumsCheckBox.gsignalConnect("toggled", 
    G_CALLBACK(showLineNums_Toggled), nil)
  showLineNumsHBox.packStart(showLineNumsCheckBox, false, false, 20)
  showLineNumsCheckBox.show()
  
  # highlightCurrentLine - checkbox
  var hlCurrLineHBox = hboxNew(false, 0)
  editorVBox.packStart(hlCurrLineHBox, false, false, 0)
  hlCurrLineHBox.show()
  
  var hlCurrLineCheckBox = checkButtonNew("Highlight selected line")
  hlCurrLineCheckBox.setActive(win.globalSettings.highlightCurrentLine)
  discard hlCurrLineCheckBox.gsignalConnect("toggled", 
    G_CALLBACK(hlCurrLine_Toggled), nil)
  hlCurrLineHBox.packStart(hlCurrLineCheckBox, false, false, 20)
  hlCurrLineCheckBox.show()
  
  # showRightMargin - checkbox
  var showMarginHBox = hboxNew(false, 0)
  editorVBox.packStart(showMarginHBox, false, false, 0)
  showMarginHBox.show()
  
  var showMarginCheckBox = checkButtonNew("Show right margin")
  showMarginCheckBox.setActive(win.globalSettings.rightMargin)
  discard showMarginCheckBox.gsignalConnect("toggled", 
    G_CALLBACK(showMargin_Toggled), nil)
  showMarginHBox.packStart(showMarginCheckBox, false, false, 20)
  showMarginCheckBox.show()
  
  # bracketMatching - checkbox
  var brackMatchHBox = hboxNew(false, 0)
  editorVBox.packStart(brackMatchHBox, false, false, 0)
  brackMatchHBox.show()
  
  var brackMatchCheckBox = checkButtonNew("Enable bracket matching")
  brackMatchCheckBox.setActive(win.globalSettings.highlightMatchingBrackets)
  discard brackMatchCheckBox.gsignalConnect("toggled", 
    G_CALLBACK(brackMatch_Toggled), nil)
  brackMatchHBox.packStart(brackMatchCheckBox, false, false, 20)
  brackMatchCheckBox.show()
  
  # autoIndent - checkbox
  var autoIndentHBox = hboxNew(false, 0)
  editorVBox.packStart(autoIndentHBox, false, false, 0)
  autoIndentHBox.show()
  
  var autoIndentCheckBox = checkButtonNew("Enable auto indent")
  autoIndentCheckBox.setActive(win.globalSettings.autoIndent)
  discard autoIndentCheckBox.gsignalConnect("toggled", 
    G_CALLBACK(autoIndent_Toggled), nil)
  autoIndentHBox.packStart(autoIndentCheckBox, false, false, 20)
  autoIndentCheckBox.show()

  # suggestFeature - checkbox
  var suggestFeatureHBox = hboxNew(false, 0)
  editorVBox.packStart(suggestFeatureHBox, false, false, 0)
  suggestFeatureHBox.show()
  
  var suggestFeatureCheckBox = checkButtonNew("Enable suggest feature")
  suggestFeatureCheckBox.setActive(win.globalSettings.suggestFeature)
  discard suggestFeatureCheckBox.gsignalConnect("toggled", 
    G_CALLBACK(suggestFeature_Toggled), nil)
  suggestFeatureHBox.packStart(suggestFeatureCheckBox, false, false, 20)
  suggestFeatureCheckBox.show()

  # show close button on all tabs - checkbox
  var showCloseOnAllTabsHBox = hboxNew(false, 0)
  editorVBox.packStart(showCloseOnAllTabsHBox, false, false, 0)
  showCloseOnAllTabsHBox.show()
  
  var showCloseOnAllTabsCheckBox = checkButtonNew("Show close button on all tabs")
  showCloseOnAllTabsCheckBox.setActive(win.globalSettings.showCloseOnAllTabs)
  discard showCloseOnAllTabsCheckBox.gsignalConnect("toggled", 
    G_CALLBACK(showCloseOnAllTabs_Toggled), nil)
  showCloseOnAllTabsHBox.packStart(showCloseOnAllTabsCheckBox, false, false, 20)
  showCloseOnAllTabsCheckBox.show()

var
  dialog: gtk2.PWindow

proc closeDialog(widget: PWidget, user_data: PGpointer) =
  win.globalSettings.nimrodCmd = $nimrodEdit.getText()
  win.globalSettings.customCmd1 = $custom1Edit.getText()
  win.globalSettings.customCmd2 = $custom2Edit.getText()
  win.globalSettings.customCmd3 = $custom3Edit.getText()

  gtk2.PObject(dialog).destroy()

proc showSettings*(aWin: var utils.MainWin) =
  win = addr(aWin)  # This has to be a pointer
                    # Because i need the settings to be changed
                    # in aporia.nim not in here.

  dialog = windowNew(gtk2.WINDOW_TOPLEVEL)
  dialog.setDefaultSize(330, 400)
  dialog.setSizeRequest(330, 400)
  dialog.setTransientFor(win.w)
  dialog.setResizable(false)
  dialog.setTitle("Settings")
  dialog.setTypeHint(WINDOW_TYPE_HINT_DIALOG)

  var contentArea = vboxNew(false, 0)
  dialog.add(contentArea)
  contentArea.show()
  
  var sHBox = hboxNew(false, 0) # Just used for some padding
  contentArea.packStart(sHBox, true, true, 10)
  sHBox.show()
  
  var tabsVBox = vboxNew(false, 0) # So that HSeperator is close to the tabs
  sHBox.packStart(tabsVBox, true, true, 10)
  tabsVBox.show()
  
  var settingsTabs = notebookNew()
  tabsVBox.packStart(settingsTabs, true, true, 0)
  settingsTabs.show()
  
  var tabsBottomLine = hSeparatorNew()
  tabsVBox.packStart(tabsBottomLine, false, false, 0)
  tabsBottomLine.show()
  
  # HBox for the close button
  var bottomHBox = hboxNew(false, 0)
  contentArea.packStart(bottomHBox, false, false, 5)
  bottomHBox.show()
  
  var closeBtn = buttonNewWithMnemonic("_Close")
  discard closeBtn.gsignalConnect("clicked", 
    G_CALLBACK(closeDialog), nil)
  bottomHBox.packEnd(closeBtn, false, false, 10)
  # Change the size of the close button
  var rq1: TRequisition 
  closeBtn.sizeRequest(addr(rq1))
  closeBtn.set_size_request(rq1.width + 10, rq1.height + 4)
  closeBtn.show()
  
  initEditor(settingsTabs)
  initFontsColors(settingsTabs)
  initTools(settingsTabs)
  
  dialog.show()
