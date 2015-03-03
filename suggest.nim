#
#
#            Aporia - Nim IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import 
  gtk2, gdk2, glib2,
  strutils, osproc, os,
  utils, processes, CustomStatusBar, AutoComplete

import rst, rstast

proc escapePango(s: string): string =
  result = ""
  for i in s:
    case i
    of '<':
      result.add("&lt;")
    of '>':
      result.add("&gt;")
    of '&':
      result.add("&amp;")
    of '"':
      result.add("&quot;")
    else:
      result.add(i)

proc addSuggestItem*(win: var MainWin, name: string, markup: string,
                     tooltipText: string, color: string = "#000000") =
  var iter: TTreeIter
  var listStore = cast[PListStore](win.suggest.treeView.getModel())
  listStore.append(addr(iter))
  listStore.set(addr(iter), 0, name, 1, markup, 2, color, 3, tooltipText, -1)

proc addSuggestItem(win: var MainWin, item: TSuggestItem) =
  # TODO: Escape tooltip text for pango markup.
  var markup = "<b>$1</b>" % [escapePango(item.nmName)]
  case item.nodeType
  of "skProc", "skTemplate", "skIterator":
    markup = "$1$2" % [escapePango(item.nmName), item.nimType.replaceWord("proc ","")]
  of "skField":
    markup = "<i>$1 - $2</i>" % [escapePango(item.nmName), item.nimType]
  win.addSuggestItem(item.nmName, markup, item.nimType)

proc getIterGlobalCoords(iter: PTextIter, tab: Tab): tuple[x, y: int32] =
  # Calculate the location of the suggest dialog.
  var iterLoc: TRectangle
  tab.sourceView.getIterLocation(iter, addr(iterLoc))

  var winX, winY: gint
  tab.sourceView.bufferToWindowCoords(TEXT_WINDOW_WIDGET, iterLoc.x, iterLoc.y,
                                     addr(winX), addr(winY))
  
  var mainGWin = tab.sourceView.getWindow(TEXT_WINDOW_WIDGET)
  var mainLocX, mainLocY: gint
  discard mainGWin.getOrigin(addr(mainLocX), addr(mainLocY))
  
  # - Get the size of the left window(Line numbers) too.
  var leftGWin = tab.sourceView.getWindow(TEXT_WINDOW_LEFT)
  var leftWidth, leftHeight: gint
  {.warning: "get_size is deprecated, get_width should be used".}
  # TODO: This is deprecated, GTK version 2.4 has get_width/get_height
  leftGWin.getSize(addr(leftWidth), addr(leftHeight))

  return (mainLocX + leftWidth + iterLoc.x, mainLocY + winY + iterLoc.height)

proc moveSuggest*(win: var MainWin, start: PTextIter, tab: Tab) =
  var (x, y) = getIterGlobalCoords(start, tab)
  
  win.suggest.dialog.move(x, y)

proc doMoveSuggest*(win: var MainWin) =
  var current = win.sourceViewTabs.getCurrentPage()
  var tab     = win.tabs[current]
  var start: TTextIter
  # Get the iter at the cursor position.
  tab.buffer.getIterAtMark(addr(start), tab.buffer.getInsert())
  moveSuggest(win, addr(start), tab)

proc parseIDEToolsLine*(cmd, line: string, item: var TSuggestItem): bool =
  if line.startsWith(cmd):
    var s = line.split('\t')
    assert s.len == 8
    item.nodeType = s[1]
    item.name = s[2]
    item.nimType = s[3]
    item.file = s[4]
    item.line = int32(s[5].parseInt())
    item.col = int32(s[6].parseInt())
    item.docs = unescape(s[7])

    # Get the name without the module name in front of it.
    var dots = item.name.split('.')
    if dots.len() == 2:
      item.nmName = item.name[dots[0].len()+1.. -1]
    else:
      echod("[Suggest] Unknown module name for ", item.name)
      item.nmName = item.name

    result = true

proc clear*(suggest: var TSuggestDialog) =
  var treeModel = suggest.treeView.getModel()
  # TODO: Why do I have to cast it? Why can't I just do PListStore(treeModel)?
  cast[PListStore](treeModel).clear()
  suggest.items = @[]
  suggest.allItems = @[]

proc show*(suggest: var TSuggestDialog) =
  if not suggest.shown and suggest.items.len() > 0:
    var selection = suggest.treeview.getSelection()  
    var selectedPath = tree_path_new_first()
    selection.selectPath(selectedPath)
    suggest.treeview.scroll_to_cell(selectedPath, nil, false, 0.5, 0.5)
  
    suggest.shown = true
    suggest.dialog.show()

proc hide*(suggest: var TSuggestDialog) =
  if suggest.shown:
    echod("[Suggest] Hide")
    suggest.shown = false
    suggest.dialog.hide()
    # Hide the tooltip too.
    suggest.tooltip.hide()

proc getFilter(win: var MainWin): string =
  # Get text before the cursor, up to a dot.
  var current = win.sourceViewTabs.getCurrentPage()
  var tab     = win.tabs[current]
  var cursor: TTextIter
  # Get the iter at the cursor position.
  tab.buffer.getIterAtMark(addr(cursor), tab.buffer.getInsert())
  
  # Search backwards for a dot.
  var startMatch: TTextIter
  var endMatch: TTextIter
  var matched = (addr(cursor)).backwardSearch(".", TEXT_SEARCH_TEXT_ONLY,
                                addr(startMatch), addr(endMatch), nil)
  
  if not matched:
    return ""
  result = $((addr(endMatch)).getText(addr(cursor)))

proc filterSuggest*(win: var MainWin) =
  ## Filters the current suggest items after whatever is behind the cursor.

  var text = getFilter(win)
  win.suggest.currentFilter = normalize($text)
  # Filter the items.
  var allItems = win.suggest.allItems
  win.suggest.clear()
  var newItems: seq[TSuggestItem] = @[]
  for i in items(allItems):
    if normalize(i.nmName).startsWith(normalize($text)):
      newItems.add(i)
      win.addSuggestItem(i)
  win.suggest.items = newItems
  win.suggest.allItems = allItems

  # Hide the tooltip
  win.suggest.tooltip.hide()

  if win.suggest.items.len() == 0 and win.suggest.gotAll:
    if text.len > 0:
      win.statusbar.setTemp("Filter gives no suggest items.", UrgNormal)
    win.suggest.hide()

proc asyncGetSuggest(win: var MainWin, file, projectFile, addToPath: string,
                     line, column: int) =
  #let sugCmd = win.getCmd("$findExe(nim)", "") &
  #      " idetools --path:$4 --track:$1,$2,$3 --suggest $5" %
  #      [file, $(line+1), $column, addToPath,
  #       if projectFile != "": projectFile else: file]

  # Verify the presence of nimsuggest in the path
  if findExe("nimsuggest") == "":
    win.statusbar.setTemp("Could not find NimSuggest in PATH.", UrgError)
    return

  let sugCmd = "sug \"$1\":$2:$3\c\l" % [file, $(line+1), $column]

  # Start NimSuggest if this is the first request.
  if not win.tempStuff.autoComplete.isThreadRunning:
    win.tempStuff.autoComplete.startThread(projectFile)

  var winPtr = addr win

  proc onSugLine(line: string) {.closure.} =
    template win: expr = winPtr[]
    var item: TSuggestItem
    if parseIDEToolsLine("sug", line, item):
      win.suggest.allItems.add(item)
      let text = getFilter(win)
      if normalize(item.nmName).startsWith(normalize(text)):
        win.suggest.items.add(item)
        win.addSuggestItem(item)
      win.suggest.show()
      win.doMoveSuggest()

  proc onSugExit(exit: int) {.closure.} =
    var win = winPtr[]
    win.suggest.gotAll = true
    if win.suggest.allItems.len == 0:
      win.statusbar.setTemp("No items found for suggest.", UrgError)

  proc onSugError(error: string) {.closure.} =
    var win = winPtr[]
    win.statusbar.setTemp("Suggest: " & error, UrgError)

  # Check if a suggest request is already running:
  if win.tempStuff.autocomplete.isTaskRunning:
    win.tempStuff.autocomplete.stopTask()
  else:
    win.tempStuff.autoComplete.startTask(sugCmd, onSugLine, onSugExit,
        onSugError)

proc populateSuggest*(win: var MainWin, start: PTextIter, tab: Tab): bool = 
  ## Starts the request for suggest items asynchronously.
  
  var aporiaTmpDir = getTempDir() / "aporia"
  var prefixDir = aporiaTmpDir / "suggest"
  
  # Create /tmp/aporia if it doesn't exist
  if not existsDir(aporiaTmpDir):
    createDir(prefixDir)
  
  # Remove and Create /tmp/aporia/suggest
  if existsDir(prefixDir):
    # Empty this to get rid of stale files.
    removeDir(prefixDir)
  # Recreate it.
  createDir(prefixDir)
  
  if tab.filename != "":
    var currentTabSplit = splitFile(tab.filename)
  
    var (projectFile, projectCfgFile) = findProjectFile(tab.filename.splitFile.dir)
    let splitPrjF = splitFile(projectFile)
    if projectFile != "":
      projectFile = prefixDir / splitPrjF.name & splitPrjF.ext
    else:
      projectFile = prefixDir / currentTabSplit.name & currentTabSplit.ext
    
    echod("[Suggest] Project cfg file is: ", projectCfgFile)
    echod("[Suggest] Project file is: ", projectFile)
    
    # Save tabs that are in the same directory as the file
    # being suggested to /tmp/aporia/suggest
    var alreadySaved: seq[string] = @[]
    for t in items(win.tabs):
      if t.filename != "" and t.filename.splitFile.dir == currentTabSplit.dir:
        var f: TFile
        var fileSplit = splitFile(t.filename)
        if fileSplit.ext != ".nim": continue
        echod("Saving ", prefixDir / fileSplit.name & fileSplit.ext)
        if f.open(prefixDir / fileSplit.name & fileSplit.ext, fmWrite):
          # Save everything.
          # - Get the text from the TextView.
          var startIter: TTextIter
          t.buffer.getStartIter(addr(startIter))
          
          var endIter: TTextIter
          t.buffer.getEndIter(addr(endIter))
          
          var text = t.buffer.getText(addr(startIter), addr(endIter), false)
          
          # - Save it.
          f.write(text)
          
          alreadySaved.add(t.filename)
        else:
          win.statusbar.setTemp("Unable to save one or more files for suggest. Suggest may not be activated.", UrgError, 5000)
          echod("[Warning] Unable to save one or more files, suggest won't work.")
          return false
        f.close()
    
    # Copy other .nim files in the directory of the file in which suggest was
    # activated to /tmp/aporia/suggest.
    for nimfile in walkFiles(tab.filename.splitFile.dir / "*.nim"):
      if nimfile notin alreadySaved:
        var fileSplit = splitFile(nimfile)
        echod("Copying ", prefixDir / fileSplit.name & fileSplit.ext)
        copyFile(nimfile, prefixDir / fileSplit.name & fileSplit.ext)
    
    # Copy over the config file, if it exists.
    if projectCfgFile != "":
      let fileSplit = splitFile(projectCfgFile)
      copyFile(projectCfgFile, prefixDir / fileSplit.name & fileSplit.ext)
    
    var file = prefixDir / currentTabSplit.name & ".nim"
    asyncGetSuggest(win, file, projectFile, prefixDir, start.getLine(),
                    start.getLineOffset())
  else:
    # Unsaved tab.
    var f: TFile
    var filename = prefixDir / "unknown.nim"
    echod("Saving ", filename)
    if f.open(filename, fmWrite):
      # Save everything.
      # - Get the text from the TextView.
      var startIter: TTextIter
      tab.buffer.getStartIter(addr(startIter))
      
      var endIter: TTextIter
      tab.buffer.getEndIter(addr(endIter))
      
      var text = tab.buffer.getText(addr(startIter), addr(endIter), false)
      
      # - Save it.
      f.write(text)
    else:
      win.statusbar.setTemp("Unable to save one or more files for suggest. Suggest will not be activated.", UrgError, 5000)
      return false
    f.close()
    asyncGetSuggest(win, filename, "", prefixDir, start.getLine(),
                        start.getLineOffset())
  
  win.suggest.currentFilter = ""
  
  return true

proc asyncGetDef*(win: var MainWin, file: string,
                  line, column: int,
    onSugLine: proc (win: var MainWin, line: string) {.closure.},
    onSugExit: proc (win: var MainWin, exitCode: int) {.closure.},
    onSugError: proc (win: var MainWin, error: string) {.closure.}): string =

  result = ""
  # Verify the presence of nimsuggest in the path
  if findExe("nimsuggest") == "":
    win.statusbar.setTemp("Could not find NimSuggest in PATH.", UrgError)
    return

  let sugCmd = "def \"$1\":$2:$3\c\l" % [file, $(line+1), $column]

  # Start NimSuggest if this is the first request.
  if not win.tempStuff.autoComplete.isThreadRunning:
    # TODO: Get project file?
    win.tempStuff.autoComplete.startThread(file)

  var winPtr = addr win

  proc onSugLineEx(line: string) {.closure.} =
    onSugLine(winPtr[], line)

  proc onSugExitEx(exit: int) {.closure.} =
    onSugExit(winPtr[], exit)

  proc onSugErrorEx(error: string) {.closure.} =
    onSugError(winPtr[], error)

  # Check if a suggest request is already running:
  if win.tempStuff.autocomplete.isTaskRunning:
    win.tempStuff.autocomplete.stopTask()
  else:
    win.tempStuff.autoComplete.startTask(sugCmd, onSugLineEx, onSugExitEx,
        onSugErrorEx)

proc doSuggest*(win: var MainWin) =
  var current = win.sourceViewTabs.getCurrentPage()
  var tab     = win.tabs[current]
  var start: TTextIter
  # Get the iter at the cursor position.
  tab.buffer.getIterAtMark(addr(start), tab.buffer.getInsert())
  let success = win.populateSuggest(addr(start), tab)
  if not success: win.suggest.hide()

proc insertSuggestItem*(win: var MainWin, index: int) =
  var name = win.suggest.items[index].nmName
  # Remove the part that was already typed
  if win.suggest.currentFilter != "":
    assert(normalize(name).startsWith(win.suggest.currentFilter))
    name = name[win.suggest.currentFilter.len() .. -1]
  
  # We have the name of the item. Now insert it into the TextBuffer.
  var currentTab = win.sourceViewTabs.getCurrentPage()
  win.tabs[currentTab].buffer.insertAtCursor(name, int32(len(name)))
  
  # Now hide the suggest dialog and clear the items.
  win.suggest.hide()
  win.suggest.clear()

proc rstToPango(r: PRstNode, result: var string) =
  proc iterTrees(r: PRstNode, result: var string) =
    for i in r.sons:
      rstToPango(i, result)
  if r == nil: return
  case r.kind
  of rnInner, rnDefItem, rnDefName, rnLiteralBlock, rnIdx, rnRef:
    iterTrees(r, result)
  of rnLeaf:
    result.add(escapePango(r.text))
  of rnEmphasis:
    result.add("<span font_style=\"italic\">")
    iterTrees(r, result)
    result.add("</span>")
  of rnInterpretedText:
    result.add("<span font_style=\"italic\" font_weight=\"bold\">")
    iterTrees(r, result)
    result.add("</span>")
  of rnDefList, rnDefBody, rnBlockQuote:
    if result != "": result.add(" ")
    iterTrees(r, result)
  of rnParagraph:
    result.add("\n")
    iterTrees(r, result)
    result.add("\n")
  of rnLineBlock, rnBulletList:
    result.add("\n")
    iterTrees(r, result)
  of rnBulletItem:
    result.add("  ▪ ")
    iterTrees(r, result)
    result.add("\n")
  of rnLineBlockItem:
    result.add("\n<tt>")
    iterTrees(r, result)
    result.add("</tt>")
  of rnInlineLiteral:
    result.add("<tt>")
    iterTrees(r, result)
    result.add("</tt>")
  of rnStrongEmphasis:
    result.add("<span font_weight=\"ultrabold\">")
    iterTrees(r, result)
    result.add("</span>")
  of rnTripleEmphasis:
    result.add("<span font_weight=\"heavy\">")
    iterTrees(r, result)
    result.add("</span>")
  of rnCodeBlock:
    result.add("\n")
    assert r.sons[0].kind == rnDirArg
    #let lang = r.sons[0].sons[0].text
    assert r.sons[1] == nil
    assert r.sons[2].kind == rnLiteralBlock
    # TODO: Highlighting?
    result.add("<tt>")
    iterTrees(r.sons[2], result)
    result.add("</tt>")
  else:
    echo(r.kind)
    assert false

proc rstToPango(s: string): string =
  var hasToc = false
  var r = rstParse(s, "input", 0, 1, hasToc, {})
  result = ""
  rstToPango(r, result)

proc showTooltip*(win: var MainWin, tab: Tab, item: TSuggestItem,
                  selectedPath: PTreePath) =
  var markup = "<i>" & escapePango(item.nimType) & "</i>"
  if item.docs != "":
    markup.add("\n\n" & item.docs.rstToPango)
  
  win.suggest.tooltipLabel.setMarkup(markup)
  var cursor: TTextIter
  # Get the iter at the cursor position.
  tab.buffer.getIterAtMark(addr(cursor), tab.buffer.getInsert())
  # Get the location where to show the tooltip.
  var (x, y) = getIterGlobalCoords(addr(cursor), tab)
  # Get the width of the suggest dialog to move the tooltip out of the way.
  var width: gint
  win.suggest.dialog.getSize(addr(width), nil)
  x += width

  # Find the position of the selected tree item.
  var cellArea: TRectangle
  win.suggest.treeview.getCellArea(selectedPath, nil, addr(cellArea))
  y += cellArea.y

  win.suggest.tooltip.resize(1, 1) # Reset the window size. Kinda hackish D:
  win.suggest.tooltip.move(x, y)
  win.suggest.tooltip.show()
  
  tab.sourceView.grabFocus()
  assert(tab.sourceView.isFocus())

# -- Signals
proc treeView_RowActivated(tv: PTreeView, path: PTreePath, 
            column: PTreeViewColumn, win: ptr MainWin) {.cdecl.} =
  var index = path.getIndices()[]
  if win.suggest.items.len() > index:
    win[].insertSuggestItem(index)

proc treeView_SelectChanged(selection: PTreeSelection, win: ptr MainWin) {.cdecl.} =
  var selectedIter: TTreeIter
  var TreeModel: PTreeModel
  if selection.getSelected(addr(TreeModel), addr(selectedIter)):
    # Get current tab(For tooltip)
    var current = win.sourceViewTabs.getCurrentPage()
    var tab     = win.tabs[current]
    var selectedPath = TreeModel.getPath(addr(selectedIter))
    var index = selectedPath.getIndices()[]
    if win.suggest.items.len() > index:
      if win.suggest.shown:
        win[].showTooltip(tab, win.suggest.items[index], selectedPath)

proc onFocusIn(widget: PWidget, ev: PEvent, win: ptr MainWin) {.cdecl.} =
  win.w.present()
  var current = win.sourceViewTabs.getCurrentPage()
  win.tabs[current].sourceView.grabFocus()
  assert(win.tabs[current].sourceView.isFocus())

# -- GUI
proc createSuggestDialog*(win: var MainWin) =
  ## Creates the suggest dialog, it does not show it.
  
  #win.suggest.dialog = dialogNew()
  win.suggest.dialog = windowNew(gtk2.WINDOW_TOPLEVEL)

  var vbox = vboxNew(false, 0)
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
  win.suggest.dialog.setDecorated(false)
  win.suggest.dialog.setSkipTaskbarHint(true)
  discard win.suggest.dialog.signalConnect("focus-in-event",
      SIGNAL_FUNC(onFocusIn), addr(win))
  
  # TreeView & TreeModel
  # -- ScrolledWindow
  var scrollWindow = scrolledWindowNew(nil, nil)
  scrollWindow.setPolicy(POLICY_NEVER, POLICY_AUTOMATIC)
  vbox.packStart(scrollWindow, true, true, 0)
  scrollWindow.show()
  # -- TreeView
  win.suggest.treeView = treeViewNew()
  win.suggest.treeView.setHeadersVisible(false)
  #win.suggest.treeView.setHasTooltip(true)
  #win.suggest.treeView.setTooltipColumn(3)
  scrollWindow.add(win.suggest.treeView)
  
  discard win.suggest.treeView.signalConnect("row-activated",
              SIGNAL_FUNC(treeView_RowActivated), addr(win))
              
  var selection = win.suggest.treeview.getSelection()
  discard selection.gsignalConnect("changed",
              GCallback(treeView_SelectChanged), addr(win))
  
  var textRenderer = cellRendererTextNew()
  # Renderer is number 0. That's why we count from 1.
  var textColumn   = treeViewColumnNewWithAttributes("Title", textRenderer,
                     "markup", 1, "foreground", 2, nil)
  discard win.suggest.treeView.appendColumn(textColumn)
  # -- ListStore
  # There are 3 attributes. The renderer is counted. Last is the tooltip text.
  var listStore = listStoreNew(4, TypeString, TypeString, TypeString, TypeString)
  assert(listStore != nil)
  win.suggest.treeview.setModel(liststore)
  win.suggest.treeView.show()
  
  # -- Append some items.
  #win.addSuggestItem("Test!", "<b>Tes</b>t!")
  #win.addSuggestItem("Test2!", "Test2!", "#ff0000")
  #win.addSuggestItem("Test3!")
  win.suggest.items = @[]
  win.suggest.allItems = @[]
  #win.suggest.dialog.show()

  # -- Tooltip
  win.suggest.tooltip = windowNew(gtk2.WINDOW_TOPLEVEL)
  #win.suggest.tooltip.setTypeHint(WINDOW_TYPE_HINT_TOOLTIP)
  win.suggest.tooltip.setTransientFor(win.w)
  win.suggest.tooltip.setSkipTaskbarHint(true)
  win.suggest.tooltip.setDecorated(false)
  win.suggest.tooltip.setDefaultSize(250, 450)
  
  discard win.suggest.tooltip.signalConnect("focus-in-event",
    SIGNAL_FUNC(onFocusIn), addr(win))
  
  var tpVBox = vboxNew(false, 0)
  win.suggest.tooltip.add(tpVBox)
  tpVBox.show()
  
  var tpHBox = hboxNew(false, 0)
  tpVBox.packStart(tpHBox, false, false, 7)
  tpHBox.show()
  
  win.suggest.tooltipLabel = labelNew("")
  win.suggest.tooltipLabel.setLineWrap(true)
  tpHBox.packStart(win.suggest.tooltipLabel, false, false, 5)
  win.suggest.tooltipLabel.show()
