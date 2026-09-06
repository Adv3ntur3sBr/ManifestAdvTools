Set shell = CreateObject("WScript.Shell")
If WScript.Arguments.Count > 0 Then
    ps1 = WScript.Arguments(0)
    cmd = "powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File """ & ps1 & """"
    shell.Run cmd, 0, False
End If
