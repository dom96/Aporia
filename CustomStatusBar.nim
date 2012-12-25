import gtk2, glib2, times, strutils

type
  TStatusKind = enum
    StatusPerm, StatusTemp, StatusProgress
  
  TUrgency* = enum
    UrgNormal, UrgError, UrgSuccess

  TStatus = object
    text: string
    urgency: TUrgency
    case kind: TStatusKind
    of StatusPerm:
      nil
    of StatusTemp:
      timeout: int # miliseconds to keep this status
      startTime: float # Timestamp which specifies when this status was applied
    of StatusProgress:
      nil

  PCustomStatusBar* = ref object
    hbox: PHbox
    statusLabel: PLabel
    status: TStatus
    progressBar*: PProgressBar
    docInfoLabel: PLabel

proc defaultStatus(): TStatus =
  result.kind = StatusPerm
  result.text = "Ready"
  result.urgency = UrgNormal

proc initCustomStatusBar*(MainBox: PBox): PCustomStatusBar =
  ## Creates a new custom status bar.
  new(result)
  result.hbox = hboxNew(False, 0)
  
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

proc setStatus(bar: PCustomStatusBar, st: TStatus) =
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
    discard gTimeoutAddFull(GPriorityLow, 500, 
      proc (barP: pointer): bool {.cdecl.} =
        let b = cast[PCustomStatusBar](barP)
        if b.status.kind == StatusTemp:
          if epochTime() - b.status.startTime > (b.status.timeout/1000):
            b.setStatus(defaultStatus())
            return false
        else:
          return false
        result = true, addr(bar[]), nil)
  

proc setPerm*(bar: PCustomStatusBar, text: string, urgency: TUrgency) =
  ## Sets a permanent status which only gets overriden by another ``set*``.
  var st: TStatus
  st.kind = StatusPerm
  st.text = text
  st.urgency = urgency
  setStatus(bar, st)

proc setTemp*(bar: PCustomStatusBar, text: string, urgency: TUrgency, timeout: int) =
  ## Sets a temporary status, after ``timeout`` the status will be disappear
  ## automatically and the previous one will be set.
  var st: TStatus
  st.kind = StatusTemp
  st.text = text
  st.urgency = urgency
  st.timeout = timeout
  st.startTime = epochTime()
  setStatus(bar, st)
  
proc setProgress*(bar: PCustomStatusBar, text: string) =
  ## Shows the ``bar.progressbar``.
  var st: TStatus
  st.kind = StatusProgress
  st.text = text
  st.urgency = UrgNormal
  setStatus(bar, st)

proc restorePrevious*(bar: PCustomStatusBar) =
  ## Restores the previous status
  bar.setStatus(defaultStatus())

proc setDocInfo*(bar: PCustomStatusBar, line, col: int) =
  bar.docInfoLabel.setText("Ln: " & $line & " Col: " & $col)

proc setDocInfoSelected*(bar: PCustomStatusBar, frmLn, toLn, frmC, toC: int) =
  # Ln: 38 -> 39 Col: 90 -> 100; 10 selected.
  if frmLn == toLn:
    bar.docInfoLabel.setText("Ln: $1 Col: $2 -> $3; $4 selected." %
        [$frmLn, $frmC, $toC, $(toC-frmC)])
  else:
    bar.docInfoLabel.setText("Ln: $1 -> $2; $3 selected. Col: $4" %
        [$frmLn, $toLn, $((toLn-frmLn)+1), $toC])
