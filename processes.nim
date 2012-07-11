import pegs, times, osproc, streams
import gtk2, glib2
import utils


var win*: ptr utils.MainWin

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
  pegSuccess = peg"'Hint: operation successful'.*"

proc execProcAsync*(cmd: string, mode: TExecMode, ifSuccess: string = "")
proc printProcOutput(line: string) =
  # Colors
  var normalTag = createColor(win.outputTextView, "normalTag", "#3d3d3d")
  var errorTag = createColor(win.outputTextView, "errorTag", "red")
  var warningTag = createColor(win.outputTextView, "warningTag", "darkorange")
  var successTag = createColor(win.outputTextView, "successTag", "darkgreen")
  
  case win.tempStuff.execMode:
  of ExecNimrod:
    if line =~ pegLineError / pegOtherError:
      win.outputTextView.addText(line & "\n", errorTag)
      win.tempStuff.compileSuccess = false
    elif line =~ pegSuccess:
      win.outputTextView.addText(line & "\n", successTag)
      win.tempStuff.compileSuccess = true

    elif line =~ pegLineWarning:
      win.outputTextView.addText(line & "\n", warningTag)
    else:
      win.outputTextView.addText(line & "\n", normalTag)
  of ExecRun, ExecCustom:
    win.outputTextView.addText(line & "\n", normalTag)
  of ExecNone:
    assert(false)

proc peekProcOutput*(dummy: pointer): bool =
  result = True
  if win.tempStuff.execMode != ExecNone:
    var events = execThrEventChan.peek()
    
    if epochTime() - win.tempStuff.lastProgressPulse >= 0.1:
      win.bottomProgress.pulse()
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
          echod("Line is: " & event.line)
          printProcOutput(event.line)
        of EvStopped:
          echod("[Idle] Process has quit")
          win.tempStuff.execMode = ExecNone
          win.bottomProgress.hide()
          
          if event.exitCode == QuitSuccess:
            win.outputTextView.addText("> Process terminated with exit code " & 
                                             $event.exitCode & "\n", successTag)
          else:
            win.outputTextView.addText("> Process terminated with exit code " & 
                                             $event.exitCode & "\n", errorTag)
          
          # Execute another process in queue (if any)
          if win.tempStuff.ifSuccess != "" and win.tempStuff.compileSuccess:
            echod("Starting new process?")
            execProcAsync(win.tempStuff.ifSuccess, ExecRun)
  else:
    echod("idle proc exiting")
    return false

proc execProcAsync(cmd: string, mode: TExecMode, ifSuccess: string = "") =
  ## This function executes a process in a new thread, using only idle time
  ## to add the output of the process to the `outputTextview`.
  assert(win.tempStuff.execMode == ExecNone)
  
  # Reset some things; and set some flags.
  echod("Spawning new process.")
  win.tempStuff.ifSuccess = ifSuccess
  # Execute the process
  echo(cmd)
  var task: TExecThrTask
  task.typ = ThrRun
  task.command = cmd
  execThrTaskChan.send(task)
  win.tempStuff.execMode = mode
  # Output
  var normalTag = createColor(win.outputTextView, "normalTag", "#3d3d3d")
  win.outputTextView.addText("> " & cmd & "\n", normalTag)
  
  # Add a function which will be called when the UI is idle.
  win.tempStuff.idleFuncId = gIdleAdd(peekProcOutput, nil)
  echod("gTimeoutAdd id = ", $win.tempStuff.idleFuncId)

  win.bottomProgress.show()
  win.bottomProgress.pulse()
  win.tempStuff.lastProgressPulse = epochTime()

template createExecThrEvent(t: TExecThrEventType, todo: stmt): stmt =
  ## Sends a thrEvent of type ``t``, does ``todo`` before sending.
  var event: TExecThrEvent
  event.typ = t
  todo
  execThrEventChan.send(event)

proc execThreadProc(){.thread.} =
  var p: PProcess
  var o: PStream
  var started = false
  while True:
    var tasks = execThrTaskChan.peek()
    if tasks == 0 and not started: tasks = 1
    if tasks > 0:
      for i in 0..tasks-1:
        var task: TExecThrTask = execThrTaskChan.recv()
        case task.typ
        of ThrRun:
          if not started:
            p = startCmd(task.command)
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
        o.close()
        started = false
        createExecThrEvent(EvStopped):
          event.exitCode = exitCode
    
    if started:
      var line = o.readLine()
      createExecThrEvent(EvRecv):
        event.line = line

proc createProcessThreads*() =
  createThread[void](win.tempStuff.execThread, execThreadProc)
