' Remote Antigravity - Windows autostart helper.
'
' 1. Starts the PC bridge silently in the background.
' 2. Waits 5 seconds so GPU/DWM are ready (prevents the Antigravity gray screen).
' 3. Launches the Antigravity IDE normally.
'
' The script locates itself, so the repository can live in ANY folder and on
' ANY Windows user account (no machine specific paths are hardcoded).
Option Explicit

Dim fso, shell, scriptDir, repoRoot, scriptPath, pythonw, command, antigravityExe

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)  ' ...\pc_bridge
repoRoot = fso.GetParentFolderName(scriptDir)                ' ...\Remote Antigravity
scriptPath = fso.BuildPath(scriptDir, "antigravity_bridge.py")

pythonw = FindPythonw(fso, repoRoot)

shell.CurrentDirectory = scriptDir
command = """" & pythonw & """ """ & scriptPath & """"

' 1. Start PC bridge hidden
On Error Resume Next
shell.Run command, 0, False
If Err.Number <> 0 Then
    Err.Clear
End If

' 2. Give Windows Desktop, GPU drivers and DWM time to initialize
WScript.Sleep 5000

' 3. Launch Antigravity IDE normally so Electron/Chromium renders correctly
antigravityExe = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\antigravity\Antigravity.exe")
If fso.FileExists(antigravityExe) Then
    shell.Run """" & antigravityExe & """", 1, False
End If

' Prefers the repo local virtual environment, then pythonw.exe from PATH.
Function FindPythonw(fso, repoRoot)
    Dim candidates, path
    candidates = Array( _
        fso.BuildPath(repoRoot, ".venv\Scripts\pythonw.exe"), _
        fso.BuildPath(repoRoot, "venv\Scripts\pythonw.exe") _
    )
    For Each path In candidates
        If fso.FileExists(path) Then
            FindPythonw = path
            Exit Function
        End If
    Next
    FindPythonw = "pythonw.exe"
End Function

