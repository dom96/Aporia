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

proc suggestThread() {.thread.} =
  let nimBinPath = findExe("nim")
  let nimPath = nimBinPath.splitFile.dir.parentDir
  var p: Process = nil
  var o: Stream = nil

  while true:
    if not p.isNil:
      if not p.running:
        p.shutdown()
        results.send(endToken)
        p = nil
        continue

    if not o.isNil:
      if o.atEnd:
        echod("[AutoComplete] Stream is at end")
        o.close()
        o = nil
      else:
        let line = o.readLine()
        # For some reason on Linux reading from the process
        # returns an empty line sometimes.
        if line.len == 0: continue
        echod("[AutoComplete] Got line from NimSuggest (stdout): ", line.repr)

        if line.toLower().startsWith("error:"):
          results.send(errorToken & line)

    var tasks = commands.peek()
    if tasks > 0 or (o.isNil and p.isNil):
      let task = commands.recv()
      echod("[AutoComplete] Got command: ", task)
      case task
      of endToken:
        p.shutdown()
        results.send(endToken)
        p = nil
        o = nil
      of stopToken:
        # Can't do much here right now since we're not async.
        # TODO
        discard
      else:
        let projectFile = task
        let projectFileNorm = projectFile.replace('\\', '/')
        # TODO: Ensure nimPath exists.
        echod("[AutoComplete] Work Dir for NimSuggest: ", nimPath)
        echod("[AutoComplete] Project file for NimSuggest: ", projectFileNorm)
        p = startProcess(findExe("nimsuggest"), nimPath,
                             ["--port:" & $port, projectFileNorm],
                             options = {poStdErrToStdOut, poUseShell})
        echod("[AutoComplete] NimSuggest started on port ", port)
        o = p.outputStream

  echod("[AutoComplete] Process thread exiting")

proc processTask(task: string) =
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

proc socketThread() {.thread.} =
  while true:
    let task = suggestTasks.recv()
    echod("[AutoComplete] Got suggest task: ", task)
    case task
    of endToken:
      assert false
    of stopToken:
      assert false
    else:
      var success = false
      for i in 0 .. 10:
        try:
          processTask(task)
          success = true
          break
        except OSError:
          echod("[AutoComplete] Error sending task. Retrying in 500ms.")
          sleep(500)
      if not success:
        results.send(errorToken & "Couldn't connect to NimSuggest.")

proc newAutoComplete*(): AutoComplete =
  result = AutoComplete()
  createThread[void](result.thread, suggestThread)
  createThread[void](result.sockThread, socketThread)

proc startNimSuggest*(self: AutoComplete, projectFile: string) =
  assert(not self.nimSuggestRunning)
  commands.send projectFile
  self.nimSuggestRunning = true

proc peekSuggestOutput(self: AutoComplete): gboolean {.cdecl.} =
  result = true
  if not self.taskRunning and results.peek() == 0:
    # There is no suggest task running, so end this idle proc.
    echod("[AutoComplete] idleproc exiting")
    return false

  while true:
    let (available, msg) = tryRecv[string](results)
    if not available:
      break
    let cmd = msg.split("\t")[0]
    echod("[AutoComplete] SuggestOutput: Cmd: ", cmd.repr)
    echod("[AutoComplete] SuggestOutput:    Full: ", msg.repr)
    case cmd & '\t'
    of endToken:
      self.nimSuggestRunning = false
      self.taskRunning = false
      self.onSugExit(0)
      return results.peek() != 0
    of stopToken:
      self.taskRunning = false
      self.onSugExit(0)
      return false
    of errorToken:
      self.onSugError(msg.split("\t")[1])
    self.onSugLine(msg)

  if not result:
    echod("[AutoComplete] idle exiting")

proc clear(chan: var Channel[string]) =
  while true:
    let (available, msg) = tryRecv(chan)
    if not available: break
    echod("[AutoComplete] Skipped: ", msg)

proc startTask*(self: AutoComplete, task: string,
               onSugLine: proc (line: string) {.closure.},
               onSugExit: proc (exit: int) {.closure.},
               onSugError: proc (error: string) {.closure.}) =
  ## Sends a new task to nimsuggest.
  echod("[AutoComplete] Starting new task: ", task)
  assert(not self.taskRunning)
  assert(self.nimSuggestRunning)
  self.taskRunning = true
  self.onSugLine = onSugLine
  self.onSugExit = onSugExit
  self.onSugError = onSugError

  # Add a function which will be called when the UI is idle.
  discard gIdleAdd(peekSuggestOutput, cast[pointer](self))

  echod("[AutoComplete] idleAdd(peekSuggestOutput)")

  # Ensure that there is no stale results from old task.
  results.clear()

  # Send the task
  suggestTasks.send(task)

proc isTaskRunning*(self: AutoComplete): bool =
  self.taskRunning

proc isNimSuggestRunning*(self: AutoComplete): bool =
  self.nimSuggestRunning

proc stopTask*(self: AutoComplete) =
  #commands.send(stopToken)
  discard
