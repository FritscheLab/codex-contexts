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
				set setupMessage to "Create a machine-local .envrc and a folder-named VS Code workspace for identity '" & identityName & "'? Existing files will not be overwritten."
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
	set reviewFingerprint to my runCommand({launcherPath, "project-fingerprint", folderPath})
	set reviewMessage to "Folder: " & folderPath & return & "Identity: " & identityName & return & "File: .envrc" & return & return & "Read this shell file before approving it. The review opens a copy of the file as text in VS Code."

	try
		set reviewChoice to «event sysodlog» reviewMessage given «class appr»:"Review Codex Environment", «class btns»:{"Leave Unapproved", "Review in VS Code"}, «class dflt»:"Review in VS Code", «class cbtn»:"Leave Unapproved"
		if «class bhit» of reviewChoice is not "Review in VS Code" then return false
		my runCommand({launcherPath, "project-review", folderPath})

		set approvalMessage to "Folder: " & folderPath & return & return & "Approve & Open lets direnv run .envrc with your user permissions now and on future loads. It then opens VS Code with identity '" & identityName & "'. This runs outside the Codex command sandbox. Choose Leave Unapproved if the file is unclear."
		set approvalChoice to «event sysodlog» approvalMessage given «class appr»:"Approve Reviewed Environment", «class btns»:{"Leave Unapproved", "Approve & Open"}, «class dflt»:"Leave Unapproved", «class cbtn»:"Leave Unapproved"
		if «class bhit» of approvalChoice is not "Approve & Open" then return false
		my runCommand({launcherPath, "project-approve", folderPath, reviewFingerprint})
		return true
	on error errorMessage number errorNumber
		if errorNumber is -128 then return false
		error errorMessage number errorNumber
	end try
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
