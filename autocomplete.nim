## This module communicates with nimsuggest in the background.
## Take a look at the ``suggest`` module for the GUI of the suggest feature.
##
## Uses 'nimsuggest' and not 'nim idetools'

import osproc, streams, os, net, glib2, gtk2, strutils

import utils

# the compiler never produces endToken:
const
  endToken = "EOF\t"
  stopToken = "STOP\t"
  errorToken = "ERROR\t"
  port = 6000.Port

var
  commands: TChannel[string]
  results: TChannel[string]
  suggestTasks: TChannel[string]

commands.open()
results.open()
suggestTasks.open()

proc shutdown(p: Process) =
  if not p.running:
    echod("[AutoComplete] Process exited.")
  else:
    echod("[AutoComplete] Process Shutting down.")
    p.terminate()
    discard p.waitForExit()
    p.close()

proc suggestThread(projectFile: string) {.thread.} =
  let nimBinPath = findExe("nim")
  let nimPath = nimBinPath.splitFile.dir.parentDir
  let projectFileNorm = projectFile.replace('\\', '/')
  # TODO: Ensure nimPath exists.
  echod("[AutoComplete] Work Dir for NimSuggest: ", nimPath)
  echod("[AutoComplete] Project file for NimSuggest: ", projectFileNorm)
  var p = startProcess(findExe("nimsuggest"), nimPath,
                       ["--port:" & $port, projectFileNorm],
                       options = {poStdErrToStdOut, poUseShell})
  echod("[AutoComplete] NimSuggest started on port ", port)
  var o = p.outputStream

  while true:
    if not p.running:
      p.shutdown()
      results.send(endToken)
      break

    let line = o.readLine()
    echod("[AutoComplete] Got line from NimSuggest (stdout): ", line)
    if line.toLower().startsWith("error:"):
      results.send(errorToken & line)

    var tasks = commands.peek()
    if tasks > 0:
      let task = commands.recv()
      echod("[AutoComplete] Got command: ", task)
      case task
      of endToken:
        p.shutdown()
        results.send(endToken)
        echod("[AutoComplete] Process thread exiting")
        break
      of stopToken:
        # Can't do much here right now since we're not async.
        # TODO
        discard
    #os.sleep(50)

proc socketThread() {.thread.} =
  while true:
    let task = suggestTasks.recv()
    echod("[AutoComplete] Got suggest task: ", task)
    case task
    of endToken:
      break
    of stopToken:
      assert false
    else:
      var socket = newSocket()
      socket.connect("localhost", port)
      echod("[AutoComplete] Socket connected")
      socket.send(task & "\c\l")
      while true:
        var line = ""
        socket.readLine(line)
        echod("[AutoComplete] Recv line: \"", line, "\"")
        if line.len == 0: break
        results.send(line)
      socket.close()
      results.send(stopToken)

proc newAutoComplete*(): AutoComplete =
  result = AutoComplete()

proc startThread*(self: AutoComplete, projectFile: string) =
  createThread(self.thread, suggestThread, projectFile)
  createThread[void](self.sockThread, socketThread)
  self.threadRunning = true

proc stopThread*(self: AutoComplete) =
  commands.send(endToken)
  suggestTasks.send(endToken)
  self.threadRunning = false
  self.taskRunning = false

proc peekSuggestOutput(self: AutoComplete): gboolean {.cdecl.} =
  result = true
  if not self.taskRunning:
    # There is no suggest task running, so end this idle proc.
    echod("[AutoComplete] idleproc exiting")
    return false

  while true:
    let (available, msg) = tryRecv[string](results)
    if not available:
      break
    case msg
    of endToken:
      self.threadRunning = false
      self.taskRunning = false
      self.onSugExit(0)
      return false
    of stopToken:
      self.taskRunning = false
      self.onSugExit(0)
      return false
    of errorToken:
      self.onSugError(msg)
    self.onSugLine(msg)

  if not result:
    echod("[AutoComplete] idle exiting")

proc startTask*(self: AutoComplete, task: string,
               onSugLine: proc (line: string) {.closure.},
               onSugExit: proc (exit: int) {.closure.},
               onSugError: proc (error: string) {.closure.}) =
  ## Sends a new task to nimsuggest.
  assert(not self.taskRunning)
  self.taskRunning = true
  self.onSugLine = onSugLine
  self.onSugExit = onSugExit
  self.onSugError = onSugError

  # Add a function which will be called when the UI is idle.
  discard gIdleAdd(peekSuggestOutput, cast[pointer](self))

  echod("[AutoComplete] idleAdd")

  # Send the task
  suggestTasks.send(task)

proc isTaskRunning*(self: AutoComplete): bool =
  self.taskRunning

proc isThreadRunning*(self: AutoComplete): bool =
  self.threadRunning

proc stopTask*(self: AutoComplete) =
  #commands.send(stopToken)
  discard
