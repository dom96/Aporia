#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2010 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import types, times, streams, parsecfg, strutils

type
  ECFGParse* = object of E_Base

proc save*(settings: TSettings) =
  var f: TFile
  if open(f, "config.conf", fmWrite):
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
    
    f.close()

proc load*(): TSettings = 
  var f = newFileStream("config.conf", fmRead)
  if f != nil:
    var p: TCfgParser
    open(p, f, "config.conf")
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
      of cfgError:
        raise newException(ECFGParse, e.msg)
      of cfgSectionStart, cfgOption:
        #
  else:
    raise newException(EIO, "Could not open configuration file.")

when isMainModule:

  echo(load().showLineNumbers)

  var s: TSettings
  s.search = "caseinsens"
  s.font = "monospace 9"
  s.colorSchemeID = "cobalt"

  save(s)
  