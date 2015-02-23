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

commands.open()
results.open()

proc readOutput(o: Stream) =
  # Check stdout for errors.
  while not o.atEnd():
    let line = o.readLine()
    echod("[AutoComplete] Got line from NimSuggest: ", line.repr)
    if line.toLower().startsWith("error:"):
      results.send(errorToken & line)

proc shutdown(p: Process) =
  if not p.running:
    echod("[AutoComplete] Process exited.")
  else:
    echod("[AutoComplete] Process Shutting down.")
    p.terminate()
    discard p.waitForExit()
    p.close()

proc suggestThread(projectFile: string) {.thread.} =
  let nimPath = findExe("nim")
  # TODO: Ensure nimPath exists.
  echod(nimPath.splitFile.dir.parentDir)
  var p = startProcess(findExe("nimsuggest"), nimPath.splitFile.dir.parentDir,
                       ["--port:" & $port, projectFile],
                       options = {poStdErrToStdOut, poUseShell})
  var o = p.outputStream

  while true:
    if not p.running:
      p.shutdown()
      results.send(endToken)
      break

    #o.readOutput

    var tasks = commands.peek()
    if tasks > 0:
      let task = commands.recv()
      echod("[AutoComplete] Got task: ", task)
      case task
      of endToken:
        p.shutdown()
        results.send(endToken)
        echod("[AutoComplete] Thread exiting")
        break
      of stopToken:
        # Can't do much here right now since we're not async.
        # TODO
        discard
      else:
        var socket = newSocket()
        socket.connect("localhost", port)
        echod("[AutoComplete] Connected")
        socket.send(task & "\c\l")
        while true:
          var line = ""
          socket.readLine(line)
          echod("[AutoComplete] Recv line: ", line.repr)
          if line.len == 0: break
          results.send(line)
        socket.close()
        results.send(stopToken)
    #os.sleep(50)

proc newAutoComplete*(): AutoComplete =
  result = AutoComplete()

proc startThread*(self: AutoComplete, projectFile: string) =
  createThread(self.thread, suggestThread, projectFile)
  self.threadRunning = true

proc stopThread*(self: AutoComplete) =
  commands.send(endToken)

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
    echod("[AutoComplete] Got Line: ", msg.repr)
    self.onSugLine(msg)

  if not result:
    echod("[AutoComplete] idle exiting")

proc startTask*(self: AutoComplete, task: string,
               onSugLine: proc (line: string) {.closure.},
               onSugExit: proc (exit: int) {.closure.},
               onSugError: proc (error: string) {.closure.}) =
  ## Sends a new task to nimsuggest.
  self.taskRunning = true
  self.onSugLine = onSugLine
  self.onSugExit = onSugExit
  self.onSugError = onSugError

  # Add a function which will be called when the UI is idle.
  discard gIdleAdd(peekSuggestOutput, cast[pointer](self))

  echod("[AutoComplete] idleAdd")

  # Send the task
  commands.send(task)

proc isTaskRunning*(self: AutoComplete): bool =
  self.taskRunning

proc isThreadRunning*(self: AutoComplete): bool =
  self.threadRunning

proc stopTask*(self: AutoComplete) =
  commands.send(stopToken)
