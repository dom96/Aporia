#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import utils, times, streams, parsecfg, strutils, os
from gtk2 import getInsert, getOffset, getIterAtMark, TTextIter

type
  ECFGParse* = object of E_Base

proc defaultSettings*(): TSettings =
  result.search = SearchCaseInsens
  result.wrapAround = true
  result.font = "Monospace 10"
  result.colorSchemeID = "classic"
  result.indentWidth = 2
  result.showLineNumbers = True
  result.highlightMatchingBrackets = True
  result.toolBarVisible = true
  result.winWidth = 800
  result.winHeight = 600
  result.autoIndent = True
  result.nimrodCmd = "$findExe(nimrod) c $#"
  result.customCmd1 = ""
  result.customCmd2 = ""
  result.customCmd3 = ""
  result.recentlyOpenedFiles = @[]
  result.singleInstancePort = 55679

proc writeSection(f: TFile, sectionName: string) =
  f.write("[")
  f.write(sectionName)
  f.write("]\n")

proc writeKeyVal(f: TFile, key, val: string) =
  f.write(key)
  f.write(" = ")
  if val.len == 0: f.write("\"\"")
  else: f.write(quoteIfContainsWhite(val))
  f.write("\n")

proc writeKeyVal(f: TFile, key: string, val: int) =
  f.write(key)
  f.write(" = ")
  f.write(val)
  f.write("\n")

proc writeKeyValRaw(f: TFile, key: string, val: string) =
  f.write(key)
  f.write(" = r")
  if val.len == 0: f.write("\"\"")
  else: f.write("\"" & val & "\"")
  f.write("\n")

proc save*(win: MainWin) =
  var settings = win.settings

  if not os.existsDir(os.getConfigDir() / "Aporia"):
    os.createDir(os.getConfigDir() / "Aporia")
  
  # Save the settings to file.
  var f: TFile
  if open(f, joinPath(os.getConfigDir(), "Aporia", "config.ini"), fmWrite):
    var confInfo = "; Aporia configuration file - Created on "
    confInfo.add($getTime())
    f.write(confInfo & "\n")

    f.writeSection("editor")
    f.writeKeyVal("font", settings.font)
    f.writeKeyVal("scheme", settings.colorSchemeID)
    f.writeKeyVal("indentWidth", settings.indentWidth)
    f.writeKeyVal("showLineNumbers", $settings.showLineNumbers)
    f.writeKeyVal("highlightMatchingBrackets", 
                  $settings.highlightMatchingBrackets)
    f.writeKeyVal("rightMargin", $settings.rightMargin)
    f.writeKeyVal("highlightCurrentLine", $settings.highlightCurrentLine)
    f.writeKeyVal("autoIndent", $settings.autoIndent)
    f.writeKeyVal("suggestFeature", $settings.suggestFeature)

    f.writeSection("other")
    f.writeKeyVal("searchMethod", $int(settings.search))
    f.writeKeyVal("singleInstancePort", $int(settings.singleInstancePort))
    
    f.writeSection("auto")
    f.write("; Stuff which is saved automatically," & 
        " like whether the window is maximized or not\n")
    f.writeKeyVal("toolBarVisible", $settings.toolBarVisible)
    f.writeKeyVal("bottomPanelVisible", $settings.bottomPanelVisible)
    f.writeKeyVal("winMaximized", $settings.winMaximized)
    f.writeKeyVal("VPanedPos", settings.VPanedPos)
    f.writeKeyVal("winWidth", settings.winWidth)
    f.writeKeyVal("winHeight", settings.winHeight)
    if settings.recentlyOpenedFiles.len() > 0:
      let frm = max(0, (win.settings.recentlyOpenedFiles.len-1)-19)
      let to  = settings.recentlyOpenedFiles.len()-1
      f.writeKeyValRaw("recentlyOpenedFiles", 
                    join(settings.recentlyOpenedFiles[frm..to], ";"))
    
    
    f.writeSection("tools")
    f.writeKeyVal("nimrodCmd", settings.nimrodCmd)
    f.writeKeyVal("customCmd1", settings.customCmd1)
    f.writeKeyVal("customCmd2", settings.customCmd2)
    f.writeKeyVal("customCmd3", settings.customCmd3)
    
    if win.Tabs.len != 0:
      f.writeSection("session")
      var tabs = "tabs = r\""
      # Save all the tabs that have a filename.
      for i in items(win.Tabs):
        if i.filename != "":
          var cursorIter: TTextIter
          i.buffer.getIterAtMark(addr(cursorIter), i.buffer.getInsert())
          var cursorPos = getOffset(addr cursorIter)
          # Kind of a messy way to save the cursor pos and filename.
          tabs.add(i.filename & "|" & $cursorPos & ";")
      f.write(tabs & "\"\n")
    
    f.close()

proc isTrue(s: string): bool = 
  result = cmpIgnoreStyle(s, "true") == 0

proc load*(lastSession: var seq[string]): TSettings = 
  var f = newFileStream(os.getConfigDir() / "Aporia" / "config.ini", fmRead)
  if f == nil: raise newException(EIO, "Could not open configuration file.")
  var p: TCfgParser
  open(p, f, joinPath(os.getConfigDir(), "Aporia", "config.ini"))
  # It is important to initialize every field, because some fields may not 
  # be set in the configuration file:
  result = defaultSettings()
  while True:
    var e = next(p)
    case e.kind
    of cfgEof:
      break
    of cfgKeyValuePair:
      case normalize(e.key)
      of "font": result.font = e.value
      of "scheme": result.colorSchemeID = e.value
      of "indentwidth": result.indentWidth = int32(e.value.parseInt())
      of "showlinenumbers": result.showLineNumbers = isTrue(e.value)
      of "highlightmatchingbrackets": 
        result.highlightMatchingBrackets = isTrue(e.value)
      of "rightmargin": result.rightMargin = isTrue(e.value)
      of "highlightcurrentline": result.highlightCurrentLine = isTrue(e.value)
      of "autoindent": result.autoIndent = isTrue(e.value)
      of "suggestfeature": result.suggestFeature = isTrue(e.value)
      of "searchmethod": result.search = TSearchEnum(e.value.parseInt())
      of "singleinstanceport":
        result.singleInstancePort = int32(e.value.parseInt())
      of "winmaximized": result.winMaximized = isTrue(e.value)
      of "vpanedpos": result.VPanedPos = int32(e.value.parseInt())
      of "toolbarvisible": result.toolBarVisible = isTrue(e.value)
      of "bottompanelvisible": result.bottomPanelVisible = isTrue(e.value)
      of "winwidth": result.winWidth = int32(e.value.parseInt())
      of "winheight": result.winHeight = int32(e.value.parseInt())
      of "nimrodcmd": result.nimrodCmd = e.value
      of "customcmd1": result.customCmd1 = e.value
      of "customcmd2": result.customCmd2 = e.value
      of "customcmd3": result.customCmd3 = e.value
      of "tabs":
        # Add the filepaths of the last session
        for i in e.value.split(';'):
          if i != "":
            lastSession.add(i)
      of "recentlyopenedfiles":
        for count, file in pairs(e.value.split(';')):
          if file != "":
            if count > 19: raise newException(ECFGParse, "Too many recent files")
            result.recentlyOpenedFiles.add(file)
      
    of cfgError:
      raise newException(ECFGParse, e.msg)
    of cfgSectionStart, cfgOption:
      nil

when isMainModule:
  echo(load().showLineNumbers)

