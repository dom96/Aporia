#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import 
  gtk2, gdk2, glib2,
  strutils, osproc, os,
  types

when not defined(os.findExe): 
  proc findExe*(exe: string): string = 
    ## returns "" if the exe cannot be found
    result = addFileExt(exe, os.exeExt)
    if ExistsFile(result): return
    var path = os.getEnv("PATH")
    for candidate in split(path, pathSep): 
      var x = candidate / result
      if ExistsFile(x): return x
    result = ""

proc addSuggestItem*(win: MainWin, name: string, markup: String,
                     color: String = "#000000") =
  var iter: TTreeIter
  var listStore = cast[PListStore](win.suggest.TreeView.getModel())
  listStore.append(addr(iter))
  listStore.set(addr(iter), 0, name, 1, markup, 2, color, -1)

proc moveSuggest*(win: MainWin, start: PTextIter, tab: Tab) =
  
  # Calculate the location of the suggest dialog.
  var iterLoc: TRectangle
  tab.sourceView.getIterLocation(start, addr(iterLoc))

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
  
  win.suggest.dialog.move(mainLocX + leftWidth + iterLoc.x,
                          mainLocY + winY + iterLoc.height)
  
proc execNimSuggest(file, addToPath: string, line: int, column: int): 
    seq[TSuggestItem] =
  result = @[]
  echo(findExe("nimrod") & 
                " idetools --path:$4 --path:$5 --track:$1,$2,$3 --suggest $1" % 
                [file, $(line+1), $column, getTempDir(), addToPath])
  var output = execProcess(findExe("nimrod") & 
                " idetools --path:$4 --path:$5 --track:$1,$2,$3 --suggest $1" % 
                [file, $(line+1), $column, getTempDir(), addToPath])

  for line in splitLines(output):
    echo(repr(line))
    if line.startswith("sug\t"):
      var s = line.split('\t')
      if s.len == 7:
        var item: TSuggestItem
        item.nodeType = s[1]
        item.name = s[2]
        item.nimType = s[3]
        item.file = s[4]
        item.line = s[5].parseInt()
        item.col = s[6].parseInt()
        
        # Get the name without the module name in front of it.
        var dots = item.name.split('.')
        if dots.len() == 2:
          item.nmName = item.name[dots[0].len()+1.. -1]
        else:
          echo("[Suggest] Skipping ", item.name)
          continue
        
        result.add(item)

proc populateSuggest*(win: var MainWin, start: PTextIter, tab: Tab): bool = 
  ## Populates the suggestDialog with items, returns true if at least one item 
  ## has been added.
  if tab.filename == "": return False
  # Save all tabs *THAT HAVE A FILENAME* to /tmp
  for t in items(win.Tabs):
    if t.filename != "":
      var f: TFile
      if f.open(getTempDir() / splitFile(t.filename).name & ".nim", fmWrite):
        # Save everything.
        # - Get the text from the TextView.
        var startIter: TTextIter
        t.buffer.getStartIter(addr(startIter))
        
        var endIter: TTextIter
        t.buffer.getEndIter(addr(endIter))
        
        var text = t.buffer.getText(addr(startIter), addr(endIter), False)

        # - Save it.
        f.write(text)
      else:
        echo("[Warning] Unable to save one or more files, suggest won't work.")
        return False
      f.close()
  
  var file = getTempDir() / splitFile(tab.filename).name & ".nim"
  win.suggest.items = execNimSuggest(file, splitFile(tab.filename).dir,
                                     start.getLine(),
                                     start.getLineOffset())
  
  if win.suggest.items.len == 0:
    echo("[Warning] No items found for suggest")
    return False
  
  # Remove the temporary file.
  #removeFile(file)
  
  for i in items(win.suggest.items):
    win.addSuggestItem(i.nmName, "<b>$1</b>" % [i.nmName])

  return True

proc clear*(suggest: var TSuggestDialog) =
  var TreeModel = suggest.TreeView.getModel()
  # TODO: Why do I have to cast it? Why can't I just do PListStore(TreeModel)?
  cast[PListStore](TreeModel).clear()
  suggest.items = @[]

proc show*(suggest: var TSuggestDialog) =
  if not suggest.shown:
    suggest.shown = true
    suggest.dialog.show()

proc hide*(suggest: var TSuggestDialog) =
  if suggest.shown:
    suggest.shown = false
    suggest.dialog.hide()

proc doSuggest*(win: var MainWin) =
  var current = win.SourceViewTabs.getCurrentPage()
  var tab     = win.Tabs[current]
  var start: TTextIter
  # Get the iter at the cursor position.
  tab.buffer.getIterAtMark(addr(start), tab.buffer.getInsert())

  if win.populateSuggest(addr(start), tab):
    win.suggest.show()
    moveSuggest(win, addr(start), tab)
    win.Tabs[current].sourceView.grabFocus()
    assert(win.Tabs[current].sourceView.isFocus())
    win.w.present()
  else: win.suggest.hide()

when isMainModule:
  var result = execNimSuggest("aporia.nim", 633, 7)
  
  echo repr(result)






