import gtk2, glib2, times, strutils

type
  StatusKind = enum
    StatusPerm, StatusTemp, StatusProgress
  
  Urgency* = enum
    UrgNormal, UrgError, UrgSuccess

  Status = object
    text: string
    urgency: Urgency
    startTime: float # Timestamp which specifies when this status was applied, also acts as ID.
    case kind: StatusKind
    of StatusPerm:
      nil
    of StatusTemp:
      timeout: int # miliseconds to keep this status
    of StatusProgress:
      nil

  CustomStatusBar* = ref object
    hbox: PHbox
    statusLabel: PLabel
    statuses: seq[Status] # previous statuses
    status: Status
    progressBar*: PProgressBar
    docInfoLabel: PLabel

  StatusID* = distinct float

proc defaultStatus(): Status =
  result.kind = StatusPerm
  result.text = "Ready"
  result.urgency = UrgNormal
  result.startTime = epochTime()

proc initCustomStatusBar*(mainBox: PBox): CustomStatusBar =
  ## Creates a new custom status bar.
  new(result)
  result.hbox = hboxNew(false, 0)
  
  result.statusLabel = labelNew("Ready")
  result.hbox.packStart(result.statusLabel, false, false, 5)
  result.statusLabel.show()
  
  result.progressbar = progressBarNew()
  result.hbox.packStart(result.progressbar, false, false, 5)
  
  result.docInfoLabel = labelNew("Ln: 0 Col: 0")
  result.hbox.packEnd(result.docInfoLabel, false, false, 64)
  result.docInfoLabel.show()
  
  mainBox.packStart(result.hbox, false, false, 3)
  result.hbox.show()

  result.status = defaultStatus()
  result.statuses = @[]

proc restorePrevious*(bar: CustomStatusBar)
proc setStatus(bar: CustomStatusBar, st: Status) =
  if bar == nil:
    echo("[Warning] CustomStatusBar is not yet initialised. SetStatus failed.")
    return
  bar.statuses.add(bar.status)

  bar.status = st
  case st.kind
  of StatusPerm, StatusTemp:
    case st.urgency
    of UrgError:
      bar.statusLabel.setMarkup("<span bgcolor='#F20A30' fgcolor='white'>" &
          st.text & "</span>")
      bar.statusLabel.setUseMarkup(true)
    of UrgNormal:
      bar.statusLabel.setText(st.text)
      bar.statusLabel.setUseMarkup(false)
    of UrgSuccess:
      bar.statusLabel.setMarkup("<span bgcolor='#259C05' fgcolor='white'>" &
          st.text & "</span>")
      bar.statusLabel.setUseMarkup(true)
    bar.statusLabel.show()
    bar.progressBar.hide()
  of StatusProgress:
    bar.statusLabel.hide()
    bar.progressbar.show()
    bar.statusLabel.setUseMarkup(false)
    bar.progressbar.setText(st.text)
  if st.kind == StatusTemp:
    # Priority has to be high, otherwise the proc fails to be executed in some
    # cases.
    let tid = gTimeoutAddFull(GPriorityHigh, 500, 
      proc (barP: pointer): bool {.cdecl.} =
        let b = cast[CustomStatusBar](barP)
        if b.status.kind == StatusTemp:
          if epochTime() - b.status.startTime > (b.status.timeout/1000):
            b.restorePrevious()
            return false
        else:
          return false
        result = true, addr(bar[]), nil)

proc setPerm*(bar: CustomStatusBar, text: string, urgency: Urgency): StatusID {.discardable.} =
  ## Sets a permanent status which only gets overriden by another ``set*``.
  ##
  ## Returns the ID.
  var st: Status
  st.kind = StatusPerm
  st.text = text
  st.urgency = urgency
  st.startTime = epochTime()
  setStatus(bar, st)
  result = StatusID(st.startTime)

proc setTemp*(bar: CustomStatusBar, text: string, urgency: Urgency, timeout: int = 5000): StatusID {.discardable.} =
  ## Sets a temporary status, after ``timeout`` the status will be disappear
  ## automatically and the previous one will be set.
  ##
  ## Returns the ID.
  var st: Status
  st.kind = StatusTemp
  st.text = text
  st.urgency = urgency
  st.timeout = timeout
  st.startTime = epochTime()
  setStatus(bar, st)
  result = StatusID(st.startTime)
  
proc setProgress*(bar: CustomStatusBar, text: string): StatusID {.discardable.} =
  ## Shows the ``bar.progressbar``.
  ##
  ## Returns the ID.
  var st: Status
  st.kind = StatusProgress
  st.text = text
  st.urgency = UrgNormal
  st.startTime = epochTime()
  setStatus(bar, st)
  result = StatusID(st.startTime)


proc `==`*(s, s2: StatusID): bool {.borrow.}

proc delPrevious*(bar: CustomStatusBar, id: StatusID) =
  ## If ``id`` is present in the list of previous statuses. It will be deleted.
  var ix = -1
  for i in 0 .. <bar.statuses.len:
    if bar.statuses[i].startTime == float(id):
      ix = i
      break
  if ix != -1:
    bar.statuses.delete(ix)

proc statusID*(bar: CustomStatusBar): StatusID =
  ## Returns current status ID.
  return bar.status.startTime.StatusID

proc restorePrevious*(bar: CustomStatusBar) =
  ## Restore the previous status.
  if bar.statuses.len > 0:
    let prevStatus = bar.statuses.pop()
    bar.setStatus(prevStatus)
    # We don't want the current status added to bar.statuses, setStatus adds it
    # so pop it here.
    discard bar.statuses.pop()
    
proc setDocInfo*(bar: CustomStatusBar, line, col: int) =
  bar.docInfoLabel.setText("Ln: " & $line & " Col: " & $col)

proc setDocInfoSelected*(bar: CustomStatusBar, frmLn, toLn, frmC, toC: int) =
  # Ln: 38 -> 39 Col: 90 -> 100; 10 selected.
  if frmLn == toLn:
    bar.docInfoLabel.setText("Ln: $1 Col: $2 -> $3; $4 selected." %
        [$frmLn, $frmC, $toC, $(toC-frmC)])
  else:
    bar.docInfoLabel.setText("Ln: $1 -> $2; $3 selected. Col: $4" %
        [$frmLn, $toLn, $((toLn-frmLn)+1), $toC])
