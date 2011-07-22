#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import types, times, streams, parsecfg, strutils, os
from gtk2 import getInsert, getOffset, getIterAtMark, TTextIter

type
  ECFGParse* = object of E_Base

proc defaultSettings*(): TSettings =
  result.search = "caseinsens"
  result.font = "Monospace 10"
  result.colorSchemeID = "classic"
  result.indentWidth = 2
  result.showLineNumbers = True
  result.highlightMatchingBrackets = True
  result.winWidth = 800
  result.winHeight = 600
  result.autoIndent = True
  result.nimrodCmd = "$findExe(nimrod) c $#"
  result.customCmd1 = ""
  result.customCmd2 = ""
  result.customCmd3 = ""

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

    f.writeSection("other")
    f.writeKeyVal("searchMethod", settings.search)
    
    f.writeSection("auto")
    f.write("; Stuff which is saved automatically," & 
        " like whether the window is maximized or not\n")
    f.writeKeyVal("winMaximized", $settings.winMaximized)
    f.writeKeyVal("VPanedPos", settings.VPanedPos)
    f.writeKeyVal("winWidth", settings.winWidth)
    f.writeKeyVal("winHeight", settings.winHeight)
    
    f.writeSection("tools")
    f.writeKeyVal("nimrodCmd", settings.nimrodCmd)
    f.writeKeyVal("customCmd1", settings.customCmd1)
    f.writeKeyVal("customCmd2", settings.customCmd2)
    f.writeKeyVal("customCmd3", settings.customCmd3)
    
    if win.Tabs.len() != 0:
      f.writeSection("session")
      var tabs = "tabs = r\""
      # Save all the tabs that have a filename.
      for i in items(win.Tabs):
        if i.filename != "":
          var cursorIter: TTextIter
          i.buffer.getIterAtMark(addr(cursorIter), i.buffer.getInsert())
          var cursorPos = addr(cursorIter).getOffset()
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
      of "indentwidth": result.indentWidth = e.value.parseInt()
      of "showlinenumbers": result.showLineNumbers = e.value == "true"
      of "highlightmatchingbrackets": 
        result.highlightMatchingBrackets = isTrue(e.value)
      of "rightmargin": result.rightMargin = isTrue(e.value)
      of "highlightcurrentline": result.highlightCurrentLine = isTrue(e.value)
      of "autoindent": result.autoIndent = isTrue(e.value)
      of "searchmethod": result.search = e.value
      of "winmaximized": result.winMaximized = isTrue(e.value)
      of "vpanedpos": result.VPanedPos = e.value.parseInt()
      of "winwidth": result.winWidth = e.value.parseInt()
      of "winheight": result.winHeight = e.value.parseInt()
      of "nimrodcmd": result.nimrodCmd = e.value
      of "customcmd1": result.customCmd1 = e.value
      of "customcmd2": result.customCmd2 = e.value
      of "customcmd3": result.customCmd3 = e.value
      of "tabs":
        # Add the filepaths of the last session
        for i in e.value.split(';'):
          if i != "":
            lastSession.add(i)
        
    of cfgError:
      raise newException(ECFGParse, e.msg)
    of cfgSectionStart, cfgOption:
      nil

when isMainModule:
  echo(load().showLineNumbers)

