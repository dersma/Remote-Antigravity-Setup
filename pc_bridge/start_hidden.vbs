' Remote Antigravity - starts the PC bridge silently in the background.
'
' The script locates itself, so the repository can live in ANY folder and on
' ANY Windows user account (no machine specific paths are hardcoded).
Option Explicit

Dim fso, shell, scriptDir, repoRoot, scriptPath, pythonw, command

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)  ' ...\pc_bridge
repoRoot = fso.GetParentFolderName(scriptDir)                ' ...\Remote Antigravity
scriptPath = fso.BuildPath(scriptDir, "antigravity_bridge.py")

pythonw = FindPythonw(fso, repoRoot)

shell.CurrentDirectory = scriptDir
command = """" & pythonw & """ """ & scriptPath & """"

On Error Resume Next
' 0 = hidden window, False = do not wait for the process to finish
shell.Run command, 0, False
If Err.Number <> 0 Then
    MsgBox "Python konnte nicht gestartet werden." & vbCrLf & vbCrLf & _
           "Bitte zuerst 'scripts\setup_remote_antigravity.ps1' ausfuehren." & vbCrLf & _
           "Verwendeter Interpreter: " & pythonw, 16, "Remote Antigravity"
    Err.Clear
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
