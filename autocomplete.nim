# Uses 'nimsuggest' and not 'nim idetools'


# the compiler never produces EndToken:
const
  EndToken = "EOF\t"
  Port = 6000

var
  commands: TChannel[string]
  results: TChannel[string]

commands.open()
results.open()

proc flushOutput(p: Process) =
  let o = p.outputStream
  while not o.atEnd:
    discard o.readLine()

proc shutdown(p: Process) =
  if not p.running:
    echod("[Thread] Process exited.")
    p.flushOutput
  else:
    discard p.waitForExit()
    p.close()

proc runNimSuggest(projectfile: string) {.thread.} =
  var p = startProcess(bin, projectfile.splitFile.dir,
                       ["--port:" & $Port, projectfile],
                       options = {poStdErrToStdOut, poUseShell})
  var socket = newSocket()
  socket.connect("localhost", Port)
  while true:
    var tasks = commands.peek()
    if tasks > 0:
      let task = commands.recv()
      if task == EndToken:
        p.shutown
        break
      else:
        socket.send(task & "\n")
        while true:
          let line = socket.readLine()
          if line.len == 0: break
          results.send(line)
          echod(line)
    #os.sleep(50)
    p.flushOutput

proc idleProc() =
  # Add a function which will be called when the UI is idle.
  win.tempStuff.idleFuncId = gIdleAdd(peekProcOutput, addr(win))
