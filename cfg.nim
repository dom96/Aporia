#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2010 Dominik Picheta
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
  result.font = "Monospace 9"
  result.colorSchemeID = "classic"
  result.indentWidth = 2
  result.showLineNumbers = True
  result.highlightMatchingBrackets = True
  result.winWidth = 800
  result.winHeight = 600
  result.autoIndent = True

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

    f.write("[editor]\n")
    f.write("font = \"" & settings.font & "\"\n")
    f.write("scheme = \"" & settings.colorSchemeID & "\"\n")
    f.write("indentWidth = " & $settings.indentWidth & "\n")
    f.write("showLineNumbers = " & $settings.showLineNumbers & "\n")
    f.write("highlightMatchingBrackets = " & 
        $settings.highlightMatchingBrackets & "\n")
    f.write("rightMargin = " & $settings.rightMargin & "\n")
    f.write("highlightCurrentLine = " & $settings.highlightCurrentLine & "\n")
    f.write("autoIndent = " & $settings.autoIndent & "\n")

    f.write("[other]\n")
    f.write("searchMethod = \"" & settings.search & "\"\n")
    
    f.write("[auto]\n")
    f.write("; Stuff which is saved automatically," & 
        " like whether the window is maximized or not\n")
    f.write("winMaximized = " & $settings.winMaximized & "\n")
    f.write("VPanedPos = " & $settings.VPanedPos & "\n")
    f.write("winWidth = " & $settings.winWidth & "\n")
    f.write("winHeight = " & $settings.winHeight & "\n")
    
    if win.Tabs.len() != 0:
      f.write("[session]\n")
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

proc load*(lastSession: var seq[string]): TSettings = 
  var f = newFileStream(os.getConfigDir() / "Aporia" / "config.ini", fmRead)
  if f == nil: raise newException(EIO, "Could not open configuration file.")
  var p: TCfgParser
  open(p, f, joinPath(os.getConfigDir(), "Aporia", "config.ini"))
  while True:
    var e = next(p)
    case e.kind
    of cfgEof:
      break
    of cfgKeyValuePair:
      case e.key
      of "font":
        result.font = e.value
      of "scheme":
        result.colorSchemeID = e.value
      of "indentWidth":
        result.indentWidth = e.value.parseInt()
      of "showLineNumbers":
        result.showLineNumbers = e.value == "true"
      of "highlightMatchingBrackets":
        result.highlightMatchingBrackets = e.value == "true"
      of "rightMargin":
        result.rightMargin = e.value == "true"
      of "highlightCurrentLine":
        result.highlightCurrentLine = e.value == "true"
      of "autoIndent":
        result.autoIndent = e.value == "true"
      of "searchMethod":
        result.search = e.value
      of "winMaximized":
        result.winMaximized = e.value == "true"
      of "VPanedPos":
        result.VPanedPos = e.value.parseInt()
      of "winWidth":
        result.winWidth = e.value.parseInt()
      of "winHeight":
        result.winHeight = e.value.parseInt()
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

