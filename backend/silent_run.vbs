Set shell = CreateObject("WScript.Shell")
If WScript.Arguments.Count > 0 Then
    cmd = "powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """"
    shell.Run cmd, 0, False
End If
