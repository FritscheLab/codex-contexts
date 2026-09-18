on run
	activate
	«event sysodlog» "Use Finder to Control-click a project folder, then choose Open With > Codex Project. The app can open, set or change, and remove this repository’s per-folder Codex context." given «class appr»:"Codex Project", «class btns»:{"OK"}, «class dflt»:"OK"
end run

on open selectedItems
	activate
	repeat with selectedItem in selectedItems
		set folderPath to «class psxp» of selectedItem
		try
			set launcherPath to «class psxp» of («event sysorpth» "codex-home")
			set hasContext to my fileExists(folderPath & "/.envrc")
			set projectAction to my chooseProjectAction(hasContext)

			if projectAction is not false then
				if projectAction is "Open with current Codex context" then
					my launchProject(launcherPath, folderPath)
				else if projectAction is "Set up a Codex identity for this folder…" or projectAction is "Set or change Codex identity…" then
					if my configureProject(launcherPath, folderPath, hasContext) then
						my launchProject(launcherPath, folderPath)
					end if
				else if projectAction is "Remove Codex context from this folder…" then
					my removeProjectContext(launcherPath, folderPath)
				end if
			end if
		on error errorMessage number errorNumber
			if errorNumber is not -128 then
				«event sysodisA» "Codex Project could not complete this action" given «class mesS»:errorMessage
			end if
		end try
	end repeat
end open

on chooseProjectAction(hasContext)
	if not hasContext then return "Set up a Codex identity for this folder…"

	set actionItems to {"Open with current Codex context", "Set or change Codex identity…", "Remove Codex context from this folder…"}
	set actionChoice to «event gtqpchlt» actionItems given «class appr»:"Codex Project", «class prmp»:"This folder has a .envrc. What would you like to do?", «class inSL»:{"Open with current Codex context"}, «class okbt»:"Continue", «class cnbt»:"Cancel", «class mlsl»:false, «class empL»:false
	if actionChoice is false then return false
	return item 1 of actionChoice
end chooseProjectAction

on configureProject(launcherPath, folderPath, replacingContext)
	set listCommand to quoted form of launcherPath & " list --names"
	set identitiesText to «event sysoexec» "/bin/zsh -lc " & quoted form of listCommand
	if identitiesText is "" then
		«event sysodisA» "No configured Codex identities were found" given «class mesS»:"Create or repair an identity with codex-home, then open this folder with Codex Project again."
		return false
	end if

	set identityChoice to «event gtqpchlt» (paragraphs of identitiesText) given «class appr»:"Choose Codex Identity", «class prmp»:"Choose the identity for this folder:", «class inSL»:{}, «class okbt»:"Continue", «class cnbt»:"Cancel", «class mlsl»:false, «class empL»:false
	if identityChoice is false then return false
	set identityName to item 1 of identityChoice

	if replacingContext then
		set confirmationText to "Replace this folder’s generated Codex context with identity “" & identityName & "”? Approval for the old .envrc will be revoked. Modified, shared, tracked, or symlinked files will be refused rather than overwritten."
		set setupCommandName to "project-change"
		set confirmationButton to "Change"
		set defaultChoice to "Cancel"
	else
		set confirmationText to "Create a machine-local .envrc and a folder-named VS Code workspace for identity “" & identityName & "”? Existing files will not be overwritten."
		set setupCommandName to "project"
		set confirmationButton to "Set Up"
		set defaultChoice to "Set Up"
	end if

	set setupChoice to «event sysodlog» confirmationText given «class appr»:"Configure Codex Project?", «class btns»:{"Cancel", confirmationButton}, «class dflt»:defaultChoice, «class cbtn»:"Cancel"
	if «class bhit» of setupChoice is not confirmationButton then return false

	set projectCommand to quoted form of launcherPath & " " & setupCommandName & " " & quoted form of identityName & " " & quoted form of folderPath
	«event sysoexec» "/bin/zsh -lc " & quoted form of projectCommand

	if not my reviewAndApproveProject(launcherPath, folderPath, identityName) then
		«event sysodlog» "The project files were created, but .envrc was not approved. Choose Open with current Codex context later after reviewing and approving it with direnv." given «class appr»:"Setup Paused", «class btns»:{"OK"}, «class dflt»:"OK"
		return false
	end if
	return true
end configureProject

on reviewAndApproveProject(launcherPath, folderPath, identityName)
	set projectName to «event sysoexec» "/usr/bin/basename " & quoted form of folderPath
	set hasReviewed to false

	repeat
		if hasReviewed then
			set reviewMessage to "Review completed." & return & return & "Project: " & projectName & return & "Identity: " & identityName & return & "File: .envrc" & return & return & "Approve & Open lets direnv execute this generated file and then opens the identity-isolated VS Code workspace. Credentials remain in the identity home; they are not copied into the project."
			set reviewButtons to {"Leave Unapproved", "Review Again", "Approve & Open"}
			set defaultButtonName to "Approve & Open"
		else
			set reviewMessage to "Review the generated environment before approving it." & return & return & "Project: " & projectName & return & "Identity: " & identityName & return & "File: .envrc" & return & return & "Review in VS Code opens an exact, read-only .sh snapshot with syntax highlighting and preserved indentation. Close that review window to return here."
			set reviewButtons to {"Leave Unapproved", "Review in VS Code"}
			set defaultButtonName to "Review in VS Code"
		end if

		set reviewChoice to «event sysodlog» reviewMessage given «class appr»:"Review Codex Environment", «class btns»:reviewButtons, «class dflt»:defaultButtonName
		set chosenButton to «class bhit» of reviewChoice
		if chosenButton is "Leave Unapproved" then return false

		if chosenButton is "Review in VS Code" or chosenButton is "Review Again" then
			set reviewCommand to quoted form of launcherPath & " project-review " & quoted form of folderPath
			«event sysoexec» "/bin/zsh -lc " & quoted form of reviewCommand
			set hasReviewed to true
		else if chosenButton is "Approve & Open" then
			set allowCommand to "direnv allow " & quoted form of folderPath
			«event sysoexec» "/bin/zsh -lc " & quoted form of allowCommand
			return true
		end if
	end repeat
end reviewAndApproveProject

on removeProjectContext(launcherPath, folderPath)
	set removeChoice to «event sysodlog» "Remove this repository’s generated, untracked .envrc and Codex workspace from this folder? Its direnv approval and local Git-exclude entries will also be removed. Identities, credentials, .codex, and unrelated VS Code settings will remain." given «class appr»:"Remove Codex Context?", «class btns»:{"Cancel", "Remove"}, «class dflt»:"Cancel", «class cbtn»:"Cancel"
	if «class bhit» of removeChoice is not "Remove" then return false

	set removeCommand to quoted form of launcherPath & " project-reset " & quoted form of folderPath
	«event sysoexec» "/bin/zsh -lc " & quoted form of removeCommand
	«event sysodlog» "The generated Codex context was removed from this folder. Identity homes and credentials were not changed." given «class appr»:"Codex Context Removed", «class btns»:{"OK"}, «class dflt»:"OK"
	return true
end removeProjectContext

on launchProject(launcherPath, folderPath)
	set launchCommand to quoted form of launcherPath & " vscode-project " & quoted form of folderPath
	«event sysoexec» "/bin/zsh -lc " & quoted form of launchCommand
end launchProject

on fileExists(filePath)
	try
		set quotedPath to quoted form of filePath
		«event sysoexec» "/bin/test -e " & quotedPath & " || /bin/test -L " & quotedPath
		return true
	on error errorMessage number errorNumber
		if errorNumber is 1 then return false
		error errorMessage number errorNumber
	end try
end fileExists
