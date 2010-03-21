#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2010 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, gdk2
{.push callConv:cdecl.}

type
  TSettings* = object
    search*: string
    font*: string
    colorSchemeID*: string

var apoSettings: TSettings

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
  
  # Entry (For the font name and size, for example 'monospace 9'
  var fontEntryHBox = hboxNew(False, 0)
  fontsColorsVBox.packStart(fontEntryHBox, False, False, 0)
  fontEntryHBox.show()
  
  var fontEntry = entryNew()
  fontEntry.setText(apoSettings.font)
  fontEntryHBox.packStart(fontEntry, False, False, 20)
  fontEntry.show()

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
  fontsColorsVBox.packStart(schemeTreeHBox, False, False, 0)
  schemeTreeHBox.show()
  
  var schemeTree = treeviewNew()
  schemeTree.setHeadersVisible(False)
  var schemeTreeScrolled = scrolledWindowNew(nil, nil)
  schemeTreeScrolled.setPolicy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
  schemeTreeScrolled.setShadowType(SHADOW_IN)
  schemeTreeScrolled.add(schemeTree)
  schemeTreeHBox.packStart(schemeTreeScrolled, True, True, 20)
  schemeTreeScrolled.show()
  
  var schemeModel = listStoreNew(2, TYPE_STRING, TYPE_STRING)
  schemeTree.setModel(schemeModel)
  schemeTree.show()
  
  var renderer = cellRendererTextNew()
  var column = treeViewColumnNewWithAttributes("Schemes", renderer, "text", 1, nil)
  discard schemeTree.appendColumn(column)
  
  var iter: TTreeIter
  schemeModel.append(addr(iter))
  schemeModel.set(addr(iter), 0, "ID", 1, "Test", -1)

proc showSettings*(w: gtk2.PWindow, cSettings: TSettings) =
  apoSettings = cSettings

  var dialog = windowNew(gtk2.WINDOW_TOPLEVEL)
  dialog.setDefaultSize(300, 400)
  dialog.setSizeRequest(300, 400)
  dialog.setTransientFor(w)
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
  
  initFontsColors(settingsTabs)
  
  dialog.show()