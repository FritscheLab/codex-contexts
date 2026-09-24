on run
	activate
	«event sysodlog» "Choose a project folder in Finder and use its Open With > VS Code - NAME entry." given «class appr»:"VS Code Identity", «class btns»: {"OK"}, «class dflt»:"OK"
end run

on open selectedItems
	set bundlePath to POSIX path of (path to me)
	set resourcesPath to bundlePath & "Contents/Resources/"
	set launcherPath to resourcesPath & "codex-home"
	set identityPath to resourcesPath & "identity"
	set identityName to do shell script "/bin/cat " & quoted form of identityPath
	repeat with selectedItem in selectedItems
		set folderPath to POSIX path of selectedItem
		try
			set shellCommand to quoted form of launcherPath & " vscode " & quoted form of identityName & " " & quoted form of folderPath
			do shell script "/bin/zsh -lc " & quoted form of shellCommand
		on error errorMessage
			display alert ("VS Code - " & identityName & " could not open this folder") message errorMessage
		end try
	end repeat
end open
