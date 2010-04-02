#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2010 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import types, times, streams, parsecfg, strutils, os

type
  ECFGParse* = object of E_Base

proc defaultSettings*(): TSettings =
  result.search = "caseinsens"
  result.font = "Monospace 9"
  result.colorSchemeID = "classic"
  result.indentWidth = 2
  result.showLineNumbers = True
  result.highlightMatchingBrackets = True

proc save*(settings: TSettings) =
  # If the directory doesn't exist, create it
  if not os.existsDir(joinPath(os.getConfigDir(), "Aporia")):
    os.createDir(joinPath(os.getConfigDir(), "Aporia"))
  
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
    
    f.write("[other]\n")
    f.write("searchMethod = \"" & settings.search & "\"\n")
    
    f.write("[silent]\n")
    f.write("; Stuff which is saved automatically," & 
        " like whether the window is maximized or not\n")
    f.write("winMaximized = " & $settings.winMaximized & "\n")
    f.write("VPanedPos = " & $settings.VPanedPos & "\n")
    
    f.close()

proc load*(): TSettings = 
  var f = newFileStream(joinPath(os.getConfigDir(), "Aporia", "config.ini"), fmRead)
  if f != nil:
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
        of "searchMethod":
          result.search = e.value
        of "winMaximized":
          result.winMaximized = e.value == "true"
        of "VPanedPos":
          result.VPanedPos = e.value.parseInt()
          
      of cfgError:
        raise newException(ECFGParse, e.msg)
      of cfgSectionStart, cfgOption:
        #
  else:
    raise newException(EIO, "Could not open configuration file.")

when isMainModule:

  echo(load().showLineNumbers)

  discard """
  var s: TSettings
  s.search = "caseinsens"
  s.font = "monospace 9"
  s.colorSchemeID = "cobalt"

  save(s)"""
  