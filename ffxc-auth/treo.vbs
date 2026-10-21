' ============================================================
'  TREO ffxc-auth  -  chi can double-click file nay
'  - chay an (khong hien cua so)
'  - tu dong bat lai neu server chet (watchdog run-forever.cmd)
'  - bam nhieu lan cung khong bi chay trung
'  De TAT: double-click stop.cmd
' ============================================================
Option Explicit
Dim fso, sh, dir
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
' 0 = cua so an,  False = khong cho (chay nen)
sh.Run "cmd /c """ & dir & "\run-forever.cmd""", 0, False
