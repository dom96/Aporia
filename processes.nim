# Aporia
# Copyright (C) Dominik Picheta
# Look at copying.txt for more info.

## This module contains functions which deal with running processes,
## such as the Nim process.
## There are also some functions for gathering errors as given by the
## nim compiler and putting them into the error list.

import pegs, times, osproc, streams, parseutils, strutils, re, os
import gtk2, glib2
import utils, CustomStatusBar

# Threading channels
var execThrTaskChan: TChannel[TExecThrTask]
execThrTaskChan.open()
var execThrEventChan: TChannel[TExecThrEvent]
execThrEventChan.open()
# Threading channels END

var
  pegLineError = peg"{[^(]*} '(' {\d+} ', ' \d+ ') Error:' \s* {.*}"
  pegLineWarning = peg"{[^(]*} '(' {\d+} ', ' \d+ ') ' ('Warning:'/'Hint:') \s* {.*}"
  pegOtherError = peg"'Error:' \s* {.*}"
  pegSegFault = peg"'SIGSEGV:' \s* {.*}"
  pegSuccess = peg"'Hint: operation successful'.*"
  pegOtherHint = peg"'Hint: '.*"
  reLineMessage = re".+\(\d+,\s\d+\)"
  pegLineInfo = peg"{[^(]*} '(' {\d+} ', ' \d+ ') Info:' \s* {.*}"

proc `$`(theType: TErrorType): string =
  case theType
  of TETError: result = "Error"
  of TETWarning: result = "Warning"

proc clearErrors*(win: var MainWin) =
  var TreeModel = win.errorListWidget.getModel()
  # TODO: Why do I have to cast it? Why can't I just do PListStore(TreeModel)?
  cast[PListStore](TreeModel).clear()
  win.tempStuff.errorList = @[]

proc addError*(win: var MainWin, error: TError) =
  # Make the file path a bit shorter, so it's more readable
  var fileShort = error.file
  var mainDir = win.tabs[win.sourceViewTabs.getCurrentPage()].filename
  var i = mainDir.rfind($os.DirSep)
  if i > 0 and error.file.startsWith(mainDir.substr(0, i)):
     fileShort = "..." & fileShort.substr(i)

  var ls = cast[PListStore](win.errorListWidget.getModel())
  var iter: TTreeIter
  ls.append(addr(iter))

  if error.kind == TETError:
    ls.set(addr(iter), 0, fileShort, 1, error.line, 2, error.column, 3, $error.kind, 4, error.desc, 5, "red", -1)
  else:
    ls.set(addr(iter), 0, fileShort, 1, error.line, 2, error.column, 3, $error.kind, 4, error.desc, 5, nil, -1)

  # Scroll to last error
  var treepath = win.errorListWidget.getModel().get_path(addr(iter));
  win.errorListWidget.scrollToCell(treepath, nil, false, 0, 0)

  # Activate "Error list" tab
  if win.globalSettings.activateErrorTabOnErrors:
    win.bottomPanelTabs.setCurrentPage(1)

  win.tempStuff.errorList.add(error)

proc parseError(err: string, res: var TError) =
  ## Parses a line like:
  ##   ``a12.nim(1, 3) Error: undeclared identifier: 'asd'``
  ##
  ## or:
  ##
  ## lib/system.nim(686, 5) Error: type mismatch: got (string, int literal(5))
  ## but expected one of:
  ## <(x: pointer, y: pointer): bool
  ## <(x: UIntMax32, y: UIntMax32): bool
  ## <(x: int32, y: int32): bool
  ## <(x: float, y: float): bool
  ## <(x: T, y: T): bool
  ## <(x: int16, y: int16): bool
  ## <(x: ordinal[T], y: ordinal[T]): bool
  ## <(x: int, y: int): bool
  ## <(x: ordinal[T]): T
  ## <(x: ref T, y: ref T): bool
  ## <(x: ptr T, y: ptr T): bool
  ## <(x: char, y: char): bool
  ## <(x: string, y: string): bool
  ## <(x: bool, y: bool): bool
  ## <(x: set[T], y: set[T]): bool
  ## <(x: int64, y: int64): bool
  ## <(x: uint64, y: uint64): bool
  ## <(x: int8, y: int8): bool
  ##
  ## or:
  ##
  ## Error: execution of an external program failed
  var i = 0
  if err.startsWith("Error: "):
    res.kind = TETError
    res.desc = err[7 .. ^1]
    res.file = ""
    res.line = ""
    res.column = ""
    return

  res.file = ""
  i += parseUntil(err, res.file, '(', i)
  inc(i) # Skip (
  res.line = ""
  var lineInt = -1
  i += parseInt(err, lineInt, i)
  res.line = $lineInt
  inc(i) # Skip ,
  i += skipWhitespace(err, i)
  res.column = ""
  var colInt = -1
  i += parseInt(err, colInt, i)
  # NOTE: Aporia numbers colums from 0,
  # but Nim diagnostics column numbers start from 1
  res.column = $(max(0, colInt-1))
  inc(i) # Skip )
  i += skipWhitespace(err, i)
  var theType = ""
  i += parseUntil(err, theType, ':', i)
  case normalize(theType)
  of "error", "info":
    res.kind = TETError
  of "hint", "warning":
    res.kind = TETWarning
  else:
    echod(theType)
    assert(false)
  inc(i) # Skip :
  i += skipWhitespace(err, i)
  res.desc = err.substr(i, err.len()-1)

proc execProcAsync*(win: var MainWin, exec: PExecOptions)
proc printProcOutput(win: var MainWin, line: string) =
  ## This shouldn't have to worry about receiving broken up errors (into new lines)
  ## continuous errors should be received, errors which span multiple lines
  ## should be received as one continuous message.
  echod("Printing: ", line.repr)
  template paErr(): stmt =
    var parseRes: TError
    parseError(line, parseRes)

    win.addError(parseRes)

  # Colors
  var normalTag = createColor(win.outputTextView, "normalTag", "#3d3d3d")
  var errorTag = createColor(win.outputTextView, "errorTag", "red")
  var warningTag = createColor(win.outputTextView, "warningTag", "darkorange")
  var successTag = createColor(win.outputTextView, "successTag", "darkgreen")

  assert win.tempStuff.currentExec != nil

  case win.tempStuff.currentExec.mode:
  of ExecNim:
    if line =~ pegLineError / pegOtherError / pegLineInfo:
      win.outputTextView.addText(line & "\l", errorTag)
      paErr()
      win.tempStuff.compileSuccess = false
    elif line =~ pegSuccess:
      win.outputTextView.addText(line & "\l", successTag)
      win.tempStuff.compileSuccess = true
    elif line =~ pegLineWarning:
      win.outputTextView.addText(line & "\l", warningTag)
      paErr()
    elif line =~ pegSegFault:
      win.outputTextView.addText(line & "\l", errorTag)    
      win.tempStuff.compileSuccess = false      
    else:
      win.outputTextView.addText(line & "\l", normalTag)
  of ExecRun, ExecCustom:
    win.outputTextView.addText(line & "\l", normalTag)

proc parseCompilerOutput(win: var MainWin, event: TExecThrEvent) =
  if event.line == "" or event.line.startsWith(pegSuccess) or
      event.line =~ pegOtherHint:
    #echod(1)
    if win.tempStuff.errorMsgStarted:
      win.tempStuff.errorMsgStarted = false
      win.printProcOutput(win.tempStuff.compilationErrorBuffer.strip())
      win.tempStuff.compilationErrorBuffer = ""
    if event.line != "":
      win.printProcOutput(event.line)
  elif event.line.startsWith(reLineMessage):
    #echod(2)
    if not win.tempStuff.errorMsgStarted:
      #echod(2.1)
      win.tempStuff.errorMsgStarted = true
      win.tempStuff.compilationErrorBuffer.add(event.line & "\l")
    elif win.tempStuff.compilationErrorBuffer != "":
      #echod(2.2)
      win.printProcOutput(win.tempStuff.compilationErrorBuffer.strip())
      win.tempStuff.compilationErrorBuffer = ""
      win.tempStuff.errorMsgStarted = false
      win.printProcOutput(event.line)
    else:
      win.printProcOutput(event.line)
  else:
    #echod(3)
    if win.tempStuff.errorMsgStarted:
      win.tempStuff.compilationErrorBuffer.add(event.line & "\l")
    else:
      win.printProcOutput(event.line)

proc peekProcOutput*(win: ptr MainWin): gboolean {.cdecl.} =
  result = true
  if win.tempStuff.currentExec != nil:
    var events = execThrEventChan.peek()

    if epochTime() - win.tempStuff.lastProgressPulse >= 0.1:
      win.statusbar.progressbar.pulse()
      win.tempStuff.lastProgressPulse = epochTime()
    if events > 0:
      var successTag = createColor(win.outputTextView, "successTag",
                                   "darkgreen")
      var errorTag = createColor(win.outputTextView, "errorTag", "red")
      for i in 0..events-1:
        var event: TExecThrEvent = execThrEventChan.recv()
        case event.typ
        of EvStarted:
          win.tempStuff.execProcess = event.p
        of EvRecv:
          event.line = event.line.strip(leading = false)
          if win.tempStuff.currentExec.onLine != nil:
            win.tempStuff.currentExec.onLine(win[], win.tempStuff.currentExec, event.line)
          if win.tempStuff.currentExec.output:
            if win.tempStuff.currentExec.mode == ExecNim:
              win[].parseCompilerOutput(event)
            else:
              # TODO: Print "" as a \n?
              if event.line != "":
                win[].printProcOutput(event.line)

        of EvStopped:
          echod("[Idle] Process has quit")
          if win.tempStuff.currentExec.onExit != nil:
            win.tempStuff.currentExec.onExit(win[], win.tempStuff.currentExec, event.exitCode)

          if win.tempStuff.currentExec.output:
            if win.tempStuff.compilationErrorBuffer.len() > 0:
              win[].printProcOutput(win.tempStuff.compilationErrorBuffer)

            if event.exitCode == QuitSuccess:
              win.outputTextView.addText("> Process terminated with exit code " &
                                               $event.exitCode & "\l", successTag)
              # Activate "Output" tab, after successful compilation
              win.bottomPanelTabs.setCurrentPage(0)
            else:
              win.outputTextView.addText("> Process terminated with exit code " &
                                               $event.exitCode & "\l", errorTag)


          let runAfter = win.tempStuff.currentExec.runAfter
          let runAfterSuccess = win.tempStuff.currentExec.runAfterSuccess
          win.tempStuff.currentExec = nil
          # remove our progress status if it's in the 'previous status list'
          win.statusbar.delPrevious(win.tempStuff.progressStatusID)
          if win.statusbar.statusID == win.tempStuff.progressStatusID:
            win.statusbar.restorePrevious()
          # TODO: Remove idle proc here?

          # Execute another process in queue (if any)
          if runAfter != nil:
            if runAfterSuccess and (not win.tempStuff.compileSuccess):
              return
            echod("Exec Run-after.")
            win[].execProcAsync(runAfter)
  else:
    echod("idle proc exiting")
    return false

proc execProcAsync*(win: var MainWin, exec: PExecOptions) =
  ## This function executes a process in a new thread, using only idle time
  ## to add the output of the process to the `outputTextview`.
  assert(win.tempStuff.currentExec == nil)

  # Reset some things; and set some flags.
  # Execute the process
  win.tempStuff.currentExec = exec
  echod(exec.command)
  var task: TExecThrTask
  task.typ = ThrRun
  task.command = exec.command
  task.workDir = exec.workDir
  execThrTaskChan.send(task)
  # Output
  if exec.output:
    var normalTag = createColor(win.outputTextView, "normalTag", "#3d3d3d")
    win.outputTextView.addText("> " & exec.command & "\l", normalTag)

  # Add a function which will be called when the UI is idle.
  win.tempStuff.idleFuncId = gTimeoutAdd(50, peekProcOutput, addr(win))

  win.tempStuff.progressStatusID = win.statusbar.setProgress("Executing")
  win.statusbar.progressbar.pulse()
  win.tempStuff.lastProgressPulse = epochTime()
  # Clear errors
  win.clearErrors()

proc newExec*(command: string, workDir: string, mode: TExecMode, output = true,
              onLine: proc (win: var MainWin, opts: PExecOptions, line: string) {.closure.} = nil,
              onExit: proc (win: var MainWin, opts: PExecOptions, exitcode: int) {.closure.} = nil,
              runAfter: PExecOptions = nil, runAfterSuccess = true): PExecOptions =
  new(result)
  result.command = command
  result.workDir = workDir
  result.mode = mode
  result.output = output
  result.onLine = onLine
  result.onExit = onExit
  result.runAfter = runAfter
  result.runAfterSuccess = runAfterSuccess

template createExecThrEvent(t: TExecThrEventType, todo: stmt): stmt {.immediate.} =
  ## Sends a thrEvent of type ``t``, does ``todo`` before sending.
  var event {.inject.}: TExecThrEvent
  event.typ = t
  todo
  execThrEventChan.send(event)

proc cmdToArgs(cmd: string): tuple[bin: string, args: seq[string]] =
  var spl = cmd.split(' ')
  assert spl.len > 0
  result.bin = spl[0]
  result.args = @[]
  for i in 1 .. <spl.len:
    result.args.add(spl[i])

proc dispatchTasks(tasks: int, started: var bool, p: var Process, o: var Stream) =
  for i in 0..tasks-1:
    var task: TExecThrTask = execThrTaskChan.recv()
    case task.typ
    of ThrRun:
      if not started:
        let (bin, args) = cmdToArgs(task.command)
        p = startProcess(bin, task.workDir, args,
                         options = {poStdErrToStdOut, poUseShell})
        createExecThrEvent(EvStarted):
          event.p = p
        o = p.outputStream
        started = true
      else:
        echod("[Thread] Process already running")
    of ThrStop:
      echod("[Thread] Stopping process.")
      p.terminate()
      started = false
      o.close()
      var exitCode = p.waitForExit()
      createExecThrEvent(EvStopped):
        event.exitCode = exitCode
      p.close()

proc execThreadProc(){.thread.} =
  var p: PProcess
  var o: PStream
  var started = false
  while true:
    var tasks = execThrTaskChan.peek()
    if tasks == 0 and not started: tasks = 1
    if tasks > 0:
      try:
        dispatchTasks(tasks, started, p, o)
      except:
        echo(getCurrentException().repr)
        block:
          createExecThrEvent(EvRecv):
            event.line = "Error: Problem occurred during execution: " &
                getCurrentExceptionMsg()
        block:
          createExecThrEvent(EvStopped):
            event.exitCode = QuitFailure

    # Check if process exited.
    if started:
      if not p.running:
        echod("[Thread] Process exited.")
        if not o.atEnd:
          var line = ""
          while not o.atEnd:
            line = o.readLine()
            createExecThrEvent(EvRecv):
              event.line = line

        # Process exited.
        var exitCode = p.waitForExit()
        p.close()
        started = false
        createExecThrEvent(EvStopped):
          event.exitCode = exitCode

    if started:
      var line = o.readLine()
      createExecThrEvent(EvRecv):
        event.line = line

  

proc createProcessThreads*(win: var MainWin) =
  createThread[void](win.tempStuff.execThread, execThreadProc)
