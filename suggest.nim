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

proc addSuggestItem*(win: MainWin, item: String, color: String = "#000000") =
  var iter: TTreeIter
  win.suggest.listStore.append(addr(iter))
  win.suggest.listStore.set(addr(iter), TextAttr, item, ColorAttr, color, -1)

proc moveSuggest*(win: MainWin, start: PTextIter, tab: Tab) =
  echo("Offset: $1. Line: $2" % @[$start.getLineOffset(), $start.getLine()])
  
  # Calculate the location of the suggest dialog.
  var iterLoc: TRectangle
  tab.sourceView.getIterLocation(start, addr(iterLoc))
  echo("Buffer: $1, $2: $3, $4" % @[$iterLoc.x, $iterLoc.y, $iterLoc.width, $iterLoc.height])
  var winX, winY: gint
  tab.sourceView.bufferToWindowCoords(TEXT_WINDOW_WIDGET, iterLoc.x, iterLoc.y,
                                     addr(winX), addr(winY))
  echo("Window: $1, $2" % @[$winX, $winY])
  
  var mainGWin = tab.sourceView.getWindow(TEXT_WINDOW_WIDGET)
  var mainLocX, mainLocY: gint
  discard mainGWin.getOrigin(addr(mainLocX), addr(mainLocY))
  echo("Location: $1, $2" % @[$mainLocX, $mainLocY])
  
  # - Get the size of the left window(Line numbers) too.
  var leftGWin = tab.sourceView.getWindow(TEXT_WINDOW_LEFT)
  var leftWidth, leftHeight: gint
  {.warning: "get_size is deprecated, get_width should be used".}
  # TODO: This is deprecated, GTK version 2.4 has get_width/get_height
  leftGWin.getSize(addr(leftWidth), addr(leftHeight))
  
  echo("Setting location to: $1, $2" % @[$(mainLocX + leftWidth + iterLoc.x),
                                         $(mainLocY + iterLoc.height)])
  
  win.suggest.dialog.move(mainLocX + leftWidth + iterLoc.x,
                          mainLocY + winY + iterLoc.height)
  
proc execNimSuggest(file, addToPath: string, line: int, column: int): 
    seq[TSuggestItem] =
  result = @[]
  echo(findExe("nimrod") & 
                " idetools --path:$4 --path:$5 --track:$1,$2,$3 --suggest $1" % 
                @[file, $line, $column, getTempDir(), addToPath])
  var output = execProcess(findExe("nimrod") & 
                " idetools --path:$4 --path:$5 --track:$1,$2,$3 --suggest $1" % 
                @[file, $(line + 1), $column, getTempDir(), addToPath])

  for line in splitLines(output):
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
        tab.buffer.getStartIter(addr(startIter))
        
        var endIter: TTextIter
        tab.buffer.getEndIter(addr(endIter))
        
        var text = tab.buffer.getText(addr(startIter), addr(endIter), False)
      
        # - Save it.
        f.write(text)
      else:
        echo("[Warning] Unable to save one or more files, suggest won't work.")
        return False
  
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
    win.addSuggestItem("<b>$1</b>" % @[i.name])

  return True

when isMainModule:
  var result = execNimSuggest("aporia.nim", 633, 7)
  
  echo repr(result)






