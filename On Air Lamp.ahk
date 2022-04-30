; Get config for contacting server.
EnvGet, USERPROFILE, USERPROFILE ; e.g. c:\users\johndoe
INI_FILE := USERPROFILE "\onair.ini"
global URL_ON, URL_OFF, ON_AIR_RE, APP_NAME, ON_AIR_APPS, SAMPLE_INTERVAL_SECONDS, REDUNDANCY, WANT_REDUNDANCY
global LAST_STATUS, RECENT_OPERATIONS, RECENT_OPERATIONS_MAX_LEN
APP_NAME := "On Air Lamp 0.0.1"
ON_AIR_APPS := {}
IniRead, URL_ON, %INI_FILE%, server, url_on
IniRead, URL_OFF, %INI_FILE%, server, url_off
IniRead, ON_AIR_RE, %INI_FILE%, client, on_air_re
SAMPLE_INTERVAL_SECONDS := 3
REDUNDANCY := 0 ; Number of consecutive requests to the Pi.
WANT_REDUNDANCY := 3
LAST_STATUS := 0
RECENT_OPERATIONS := []
RECENT_OPERATIONS_MAX_LEN := 10

DetectHiddenWindows, Off

; Returns a list of the current window titles.
GetAllWindows() {
  windows := {}
  WinGet, ids, List ; get all window IDs
  Loop %ids% {
    id := ids%A_Index%
    ; Get the ancestor window because we may have dialogs titled "Open File" etc.
    ; https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getancestor
    rootID := DllCall("GetAncestor", UInt, WinExist("ahk_id" id), UInt, 3)
    WinGetTitle, rootTitle, ahk_id %rootID%
    WinGet, processName, ProcessName, ahk_id %id%
    if (rootTitle) {
      ; Store process name for debugging.
      if (!windows[rootTitle]) {
        windows[rootTitle] := {"ids": [rootID], "name": processName}
      } else {
        windows[rootTitle]["ids"].Push(rootID)
      }
    }
  }
  return windows
}

; This function does the thing.
DoTheThing() {
  onAirBefore := IsOnAir()
  ON_AIR_APPS := {}
  for title, details in GetAllWindows() {
    if (RegExMatch(title, ON_AIR_RE)) {
      ON_AIR_APPS[title] := details
    }
  }
  onAirNow := IsOnAir()
  if (onAirNow != onAirBefore) {
    REDUNDANCY := 0
  }
  if (REDUNDANCY < WANT_REDUNDANCY) {
    SendRequest(onAirNow)
    REDUNDANCY := REDUNDANCY + 1
    FormatTime, t, Time, yyyyMMdd HHmmss
    message := t " onAir=" onAirNow " status=" LAST_STATUS
    RECENT_OPERATIONS.Push(message)
    if (RECENT_OPERATIONS.Length() > RECENT_OPERATIONS_MAX_LEN) {
      RECENT_OPERATIONS.RemoveAt(1, RECENT_OPERATIONS.Length() - RECENT_OPERATIONS_MAX_LEN)
    }
  }
}

IsOnAir() {
  for ignored1, ignored2 in ON_AIR_APPS { ; Can't query object array size.
    return true
  }
  return false
}

SendRequest(onAir) {
  request := ComObjCreate("WinHttp.WinHttpRequest.5.1")
  request.open("GET", onAir ? URL_ON : URL_OFF, false)
  request.setRequestHeader("Cache-Control", "max-age=0")
  request.send()
  LAST_STATUS := request.status
}

; The main loop that does the thing.
Loop {
  DoTheThing()
  Sleep % SAMPLE_INTERVAL_SECONDS * 1000
}

DebugShowStatus() {
  text := ""
  for title, window in GetAllWindows() {
    ids := ""
    for ignored, id in window["ids"] {
      ids .= (ids ? "/" : "") id
    }
    text .= "title=" title " ids=" ids " name=" window["name"] "`n"
  }
  text .= "re=" ON_AIR_RE "`n"
  for title, details in ON_AIR_APPS {
    text .= "on air: " title " (" details["name"] ")`n"
  }
  text .= "redundancy=" REDUNDANCY "`n"
  for ignored, message in RECENT_OPERATIONS {
    text .= "recent: " message "`n"
  }

  ShowDebugGui(text)
}

ShowDebugGui(text) {
  static debugButtonOK := 0
  Gui, Debug:New,, %APP_NAME% - Debug
  Gui, Add, Edit, w700 ReadOnly, %text%
  Gui, Add, Button, w80 x310 gDebugGuiOK VdebugButtonOK, &OK
  GuiControl, Focus, debugButtonOK ; to avoid text selection
  Gui, Show
}

; --- Debug hotkeys ---

^F12::
DebugShowStatus()
return

DebugGuiOK:
DebugGuiEscape:
Gui, Debug:Destroy
return
