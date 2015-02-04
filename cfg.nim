#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import utils, times, streams, parsecfg, strutils, os
from gtk2 import getInsert, getOffset, getIterAtMark, TTextIter,
    WrapNone, WrapChar, WrapWord

type
  ECFGParse* = object of E_Base

proc defaultAutoSettings*(): TAutoSettings =
  result.search = SearchCaseInsens
  result.wrapAround = true
  result.winWidth = 800
  result.winHeight = 600

  result.recentlyOpenedFiles = @[]

proc defaultGlobalSettings*(): TGlobalSettings =
  result.selectHighlightAll = true
  result.searchHighlightAll = false
  result.font = "Monospace 10"
  result.outputFont = "Monospace 10"
  result.colorSchemeID = "piekno"
  result.indentWidth = 2
  result.showLineNumbers = true
  result.highlightMatchingBrackets = true
  result.toolBarVisible = true
  result.autoIndent = true
  result.nimrodCmd = "$findExe(nimrod) c --listFullPaths $#"
  result.customCmd1 = ""
  result.customCmd2 = ""
  result.customCmd3 = ""
  result.singleInstancePort = 55679
  result.showCloseOnAllTabs = false
  result.compileUnsavedSave = true
  result.nimrodPath = ""
  result.wrapMode = WrapNone

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

proc save(settings: TAutoSettings, win: var MainWin) =
  if not os.existsDir(os.getConfigDir() / "Aporia"):
    os.createDir(os.getConfigDir() / "Aporia")
  
  var f: TFile
  if open(f, joinPath(os.getConfigDir(), "Aporia", "config.auto.ini"), fmWrite):
    var confInfo = "; Aporia automatically generated configuration file - Last modified: "
    confInfo.add($getTime())
    f.write(confInfo & "\n")
    
    f.writeKeyVal("searchMethod", $int(settings.search))
    f.writeKeyVal("wrapAround", $settings.wrapAround)
    f.writeKeyVal("winMaximized", $settings.winMaximized)
    f.writeKeyVal("VPanedPos", settings.VPanedPos)
    f.writeKeyVal("winWidth", settings.winWidth)
    f.writeKeyVal("winHeight", settings.winHeight)
    
    f.writeKeyVal("bottomPanelVisible", $settings.bottomPanelVisible)
    if settings.recentlyOpenedFiles.len() > 0:
      let frm = max(0, (settings.recentlyOpenedFiles.len-1)-19)
      let to  = settings.recentlyOpenedFiles.len()-1
      f.writeKeyValRaw("recentlyOpenedFiles", 
                    join(settings.recentlyOpenedFiles[frm..to], ";"))

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
    
      # Save currently selected tab
      var current = win.getCurrentTab()
      f.writeKeyValRaw("lastSelectedTab", win.Tabs[current].filename)
    f.close()

proc save*(settings: TGlobalSettings) =
  if not os.existsDir(os.getConfigDir() / "Aporia"):
    os.createDir(os.getConfigDir() / "Aporia")
  
  # Save the settings to file.
  var f: TFile
  if open(f, joinPath(os.getConfigDir(), "Aporia", "config.global.ini"), fmWrite):
    var confInfo = "; Aporia global configuration file - Last modified: "
    confInfo.add($getTime())
    f.write(confInfo & "\n")

    f.writeKeyVal("font", settings.font)
    f.writeKeyVal("outputFont", settings.outputFont)
    f.writeKeyVal("scheme", settings.colorSchemeID)
    f.writeKeyVal("indentWidth", settings.indentWidth)
    f.writeKeyVal("showLineNumbers", $settings.showLineNumbers)
    f.writeKeyVal("highlightMatchingBrackets", 
                  $settings.highlightMatchingBrackets)
    f.writeKeyVal("rightMargin", $settings.rightMargin)
    f.writeKeyVal("highlightCurrentLine", $settings.highlightCurrentLine)
    f.writeKeyVal("autoIndent", $settings.autoIndent)
    f.writeKeyVal("suggestFeature", $settings.suggestFeature)
    f.writeKeyVal("showCloseOnAllTabs", $settings.showCloseOnAllTabs)

    f.writeKeyVal("selectHighlightAll", $settings.selectHighlightAll)
    f.writeKeyVal("searchHighlightAll", $settings.searchHighlightAll)
    f.writeKeyVal("singleInstancePort", $int(settings.singleInstancePort))
    f.writeKeyVal("compileUnsavedSave", $settings.compileUnsavedSave)
    f.writeKeyValRaw("nimrodPath", $settings.nimrodPath)
    f.writeKeyVal("toolBarVisible", $settings.toolBarVisible)
    f.writeKeyVal("wrapMode",
      case settings.wrapMode
      of WrapNone: "none"
      of WrapChar: "char"
      of WrapWord: "word"
      else:
        assert false; ""
    )

    f.writeKeyVal("nimrodCmd", settings.nimrodCmd)
    f.writeKeyVal("customCmd1", settings.customCmd1)
    f.writeKeyVal("customCmd2", settings.customCmd2)
    f.writeKeyVal("customCmd3", settings.customCmd3)
    
    f.close()

proc save*(win: var MainWin) =
  win.autoSettings.save(win)
  win.globalSettings.save()
  if existsFile(os.getConfigDir() / "Aporia" / "config.ini"):
    echo(os.getConfigDir() / "Aporia" / "config.ini")
    removeFile(os.getConfigDir() / "Aporia" / "config.ini")


proc isTrue(s: string): bool = 
  result = cmpIgnoreStyle(s, "true") == 0

proc loadOld(lastSession: var seq[string]): tuple[a: TAutoSettings, g: TGlobalSettings] =
  var p: TCfgParser
  var input = newFileStream(os.getConfigDir() / "Aporia" / "config.ini", fmRead)
  open(p, input, joinPath(os.getConfigDir(), "Aporia", "config.ini"))
  # It is important to initialize every field, because some fields may not 
  # be set in the configuration file:
  result.a = defaultAutoSettings()
  result.g = defaultGlobalSettings()
  while true:
    var e = next(p)
    case e.kind
    of cfgEof:
      break
    of cfgKeyValuePair:
      case normalize(e.key)
      of "font": result.g.font = e.value
      of "outputfont": result.g.outputFont = e.value
      of "scheme": result.g.colorSchemeID = e.value
      of "indentwidth": result.g.indentWidth = int32(e.value.parseInt())
      of "showlinenumbers": result.g.showLineNumbers = isTrue(e.value)
      of "highlightmatchingbrackets": 
        result.g.highlightMatchingBrackets = isTrue(e.value)
      of "rightmargin": result.g.rightMargin = isTrue(e.value)
      of "highlightcurrentline": result.g.highlightCurrentLine = isTrue(e.value)
      of "autoindent": result.g.autoIndent = isTrue(e.value)
      of "suggestfeature": result.g.suggestFeature = isTrue(e.value)
      of "showcloseonalltabs": result.g.showCloseOnAllTabs = isTrue(e.value)
      of "searchmethod": result.a.search = TSearchEnum(e.value.parseInt())
      of "selecthighlightall": result.g.selectHighlightAll = isTrue(e.value)
      of "searchhighlightall": result.g.searchHighlightAll = isTrue(e.value)
      of "singleinstanceport":
        result.g.singleInstancePort = int32(e.value.parseInt())
      of "winmaximized": result.a.winMaximized = isTrue(e.value)
      of "vpanedpos": result.a.VPanedPos = int32(e.value.parseInt())
      of "toolbarvisible": result.g.toolBarVisible = isTrue(e.value)
      of "bottompanelvisible": result.a.bottomPanelVisible = isTrue(e.value)
      of "winwidth": result.a.winWidth = int32(e.value.parseInt())
      of "winheight": result.a.winHeight = int32(e.value.parseInt())
      of "nimrodcmd": result.g.nimrodCmd = e.value
      of "customcmd1": result.g.customCmd1 = e.value
      of "customcmd2": result.g.customCmd2 = e.value
      of "customcmd3": result.g.customCmd3 = e.value
      of "tabs":
        # Add the filepaths of the last session
        for i in e.value.split(';'):
          if i != "":
            lastSession.add(i)
      of "recentlyopenedfiles":
        for count, file in pairs(e.value.split(';')):
          if file != "":
            if count > 19: raise newException(ECFGParse, "Too many recent files")
            result.a.recentlyOpenedFiles.add(file)
      of "lastselectedtab":
        result.a.lastSelectedTab = e.value
      of "compileunsavedsave":
        result.g.compileUnsavedSave = isTrue(e.value)
      of "nimrodpath":
        result.g.nimrodPath = e.value
      else:
        raise newException(ECFGParse, "Key \"" & e.key & "\" is invalid.")
    of cfgError:
      raise newException(ECFGParse, e.msg)
    of cfgSectionStart, cfgOption:
      nil
  input.close()
  p.close()

proc loadAuto(lastSession: var seq[string]): TAutoSettings =
  result = defaultAutoSettings()
  let autoPath = os.getConfigDir() / "Aporia" / "config.auto.ini"
  if not existsFile(autoPath): return
  var pAuto: TCfgParser
  var autoStream = newFileStream(autoPath, fmRead)
  open(pAuto, autoStream, autoPath)
  # It is important to initialize every field, because some fields may not 
  # be set in the configuration file:
  while true:
    var e = next(pAuto)
    case e.kind
    of cfgEof:
      break
    of cfgKeyValuePair:
      case normalize(e.key):
      of "searchmethod": result.search = TSearchEnum(e.value.parseInt())
      of "wraparound": result.wrapAround = isTrue(e.value)
      of "winmaximized": result.winMaximized = isTrue(e.value)
      of "vpanedpos": result.VPanedPos = int32(e.value.parseInt())
      of "bottompanelvisible": result.bottomPanelVisible = isTrue(e.value)
      of "winwidth": result.winWidth = int32(e.value.parseInt())
      of "winheight": result.winHeight = int32(e.value.parseInt())
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
      of "lastselectedtab":
        result.lastSelectedTab = e.value
      else:
        raise newException(ECFGParse, "Key \"" & e.key & "\" is invalid.")
    of cfgError:
      raise newException(ECFGParse, e.msg)
    of cfgSectionStart, cfgOption:
      discard

  autoStream.close()
  pAuto.close()

proc loadGlobal*(input: PStream): TGlobalSettings =
  result = defaultGlobalSettings()
  if input == nil: return
  var pGlobal: TCfgParser
  open(pGlobal, input, os.getConfigDir() / "Aporia" / "config.global.ini")
  while true:
    var e = next(pGlobal)
    case e.kind
    of cfgEof:
      break
    of cfgKeyValuePair:
      case normalize(e.key)
      of "font": result.font = e.value
      of "outputfont": result.outputFont = e.value
      of "scheme": result.colorSchemeID = e.value
      of "indentwidth": result.indentWidth = int32(e.value.parseInt())
      of "showlinenumbers": result.showLineNumbers = isTrue(e.value)
      of "highlightmatchingbrackets": 
        result.highlightMatchingBrackets = isTrue(e.value)
      of "rightmargin": result.rightMargin = isTrue(e.value)
      of "highlightcurrentline": result.highlightCurrentLine = isTrue(e.value)
      of "autoindent": result.autoIndent = isTrue(e.value)
      of "suggestfeature": result.suggestFeature = isTrue(e.value)
      of "showcloseonalltabs": result.showCloseOnAllTabs = isTrue(e.value)
      of "selecthighlightall": result.selectHighlightAll = isTrue(e.value)
      of "searchhighlightall": result.searchHighlightAll = isTrue(e.value)
      of "singleinstanceport":
        result.singleInstancePort = int32(e.value.parseInt())
      of "toolbarvisible": result.toolBarVisible = isTrue(e.value)
      of "nimrodcmd": result.nimrodCmd = e.value
      of "customcmd1": result.customCmd1 = e.value
      of "customcmd2": result.customCmd2 = e.value
      of "customcmd3": result.customCmd3 = e.value
      of "compileunsavedsave":
        result.compileUnsavedSave = isTrue(e.value)
      of "nimrodpath":
        result.nimrodPath = e.value
      of "wrapmode":
        case e.value.normalize
        of "none":
          result.wrapMode = WrapNone
        of "char":
          result.wrapMode = WrapChar
        of "word":
          result.wrapMode = WrapWord
        else:
          raise newException(ECFGParse, "WrapMode invalid, got: '" & e.value & "'")
      else:
        raise newException(ECFGParse, "Key \"" & e.key & "\" is invalid.")
    of cfgError:
      raise newException(ECFGParse, e.msg)
    of cfgSectionStart, cfgOption:
      discard
  close(pGlobal)

proc load*(lastSession: var seq[string]): tuple[a: TAutoSettings, g: TGlobalSettings] = 
  if existsFile(os.getConfigDir() / "Aporia" / "config.ini"):
    return loadOld(lastSession)
  else:
    result.a = loadAuto(lastSession)
    var globalStream = newFileStream(os.getConfigDir() / "Aporia" / "config.global.ini", fmRead)
    result.g = loadGlobal(globalStream)
    if globalStream != nil:
      globalStream.close()

