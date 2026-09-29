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
			if not my fileExists(folderPath & "/.envrc") then
				activate
				set setupMessage to "Create a machine-local .envrc and a folder-named VS Code workspace for identity “" & identityName & "”? Existing files will not be overwritten."
				set setupChoice to display dialog setupMessage with title "Configure Codex Project?" buttons {"Cancel", "Set Up"} default button "Set Up" cancel button "Cancel"
				if button returned of setupChoice is "Set Up" then
					my runCommand({launcherPath, "project", identityName, folderPath})
					if my approveProject(launcherPath, folderPath, identityName) then
						my runCommand({launcherPath, "vscode", identityName, folderPath})
					else
						display dialog "The project files are configured, but .envrc is not approved. Approve it with direnv before opening this folder with VS Code - " & identityName & "." with title "Setup Paused" buttons {"OK"} default button "OK"
					end if
				end if
			else
				my runCommand({launcherPath, "vscode", identityName, folderPath})
			end if
		on error errorMessage number errorNumber
			if errorNumber is not -128 then display alert ("VS Code - " & identityName & " could not open this folder") message errorMessage
		end try
	end repeat
end open

on approveProject(launcherPath, folderPath, identityName)
	set projectName to do shell script "/usr/bin/basename " & quoted form of folderPath
	set approvalMessage to "Project: " & projectName & return & "Identity: " & identityName & return & "File: .envrc" & return & return & "Approve & Open lets direnv execute the generated file and opens VS Code with this identity. Review in VS Code lets you inspect a read-only copy first. Credentials remain in the identity home."

	repeat
		try
			set reviewChoice to display dialog approvalMessage with title "Approve Codex Environment" buttons {"Leave Unapproved", "Review in VS Code", "Approve & Open"} default button "Approve & Open" cancel button "Leave Unapproved"
		on error errorMessage number errorNumber
			if errorNumber is -128 then return false
			error errorMessage number errorNumber
		end try
		set chosenButton to button returned of reviewChoice
		if chosenButton is "Leave Unapproved" then return false

		if chosenButton is "Review in VS Code" then
			my runCommand({launcherPath, "project-review", folderPath})
		else if chosenButton is "Approve & Open" then
			my runCommand({"direnv", "allow", folderPath})
			return true
		end if
	end repeat
end approveProject

on runCommand(commandArguments)
	set shellCommand to ""
	repeat with commandArgument in commandArguments
		set shellCommand to shellCommand & " " & quoted form of (commandArgument as text)
	end repeat
	return do shell script "/bin/zsh -lc " & quoted form of shellCommand
end runCommand

on fileExists(filePath)
	try
		set quotedPath to quoted form of filePath
		do shell script "/bin/test -e " & quotedPath & " || /bin/test -L " & quotedPath
		return true
	on error errorMessage number errorNumber
		if errorNumber is 1 then return false
		error errorMessage number errorNumber
	end try
end fileExists
