(*
 * apple-notes-export.applescript
 * Kiln — export Apple Notes to JSON-lines on stdout.
 * See macos-data-sources/SKILL.md §3 for context.
 *
 * Usage (from Swift sidecar):
 *   osascript apple-notes-export.applescript > notes.jsonl
 *
 * First invocation prompts the user to grant Automation → Notes in
 * System Settings → Privacy & Security → Automation. After grant,
 * subsequent runs are silent.
 *
 * Output: one JSON object per line with keys:
 *   id         — Notes persistent identifier (x-coredata://...)
 *   title      — note name
 *   body_html  — note body as HTML (strip on Swift side with NSAttributedString)
 *   created    — YYYY-MM-DDThh:mm:ss in the machine's local time
 *   modified   — YYYY-MM-DDThh:mm:ss
 *   folder     — folder name (e.g. "Notes", "Imported")
 *   account    — account display name (e.g. "iCloud", "On My Mac")
 *)

-- AppleScript `date` -> ISO-ish local-time string.
-- TZ fix-up is the caller's job (use the ingest machine's current offset).
on iso8601(d)
	set y to year of d as string
	set m to (month of d as integer) as string
	set dd to day of d as string
	set hh to (hours of d) as string
	set mm to (minutes of d) as string
	set ss to (seconds of d) as string
	if length of m is 1 then set m to "0" & m
	if length of dd is 1 then set dd to "0" & dd
	if length of hh is 1 then set hh to "0" & hh
	if length of mm is 1 then set mm to "0" & mm
	if length of ss is 1 then set ss to "0" & ss
	return y & "-" & m & "-" & dd & "T" & hh & ":" & mm & ":" & ss
end iso8601

-- JSON string escape: handles \, ", newline, carriage return, tab.
-- Notes bodies contain HTML which is UTF-8 safe in JSON strings, so we
-- don't escape other control chars here.
on jsonEscape(s)
	set AppleScript's text item delimiters to "\\"
	set parts to text items of s
	set AppleScript's text item delimiters to "\\\\"
	set s to parts as string
	set AppleScript's text item delimiters to "\""
	set parts to text items of s
	set AppleScript's text item delimiters to "\\\""
	set s to parts as string
	set AppleScript's text item delimiters to (ASCII character 10)
	set parts to text items of s
	set AppleScript's text item delimiters to "\\n"
	set s to parts as string
	set AppleScript's text item delimiters to (ASCII character 13)
	set parts to text items of s
	set AppleScript's text item delimiters to "\\n"
	set s to parts as string
	set AppleScript's text item delimiters to (ASCII character 9)
	set parts to text items of s
	set AppleScript's text item delimiters to "\\t"
	set s to parts as string
	set AppleScript's text item delimiters to ""
	return s
end jsonEscape

set output to ""
tell application "Notes"
	-- password protected = false skips locked notes (body is unreadable)
	repeat with n in (every note whose password protected is false)
		try
			set theID to (id of n as string)
			set theTitle to (name of n as string)
			set theBody to (body of n as string)
			set theCreated to my iso8601(creation date of n)
			set theModified to my iso8601(modification date of n)
			set theFolder to (name of (container of n) as string)
			set theAccount to (name of (account of (container of n)) as string)

			set line to "{" & ¬
				"\"id\":\"" & my jsonEscape(theID) & "\"," & ¬
				"\"title\":\"" & my jsonEscape(theTitle) & "\"," & ¬
				"\"body_html\":\"" & my jsonEscape(theBody) & "\"," & ¬
				"\"created\":\"" & theCreated & "\"," & ¬
				"\"modified\":\"" & theModified & "\"," & ¬
				"\"folder\":\"" & my jsonEscape(theFolder) & "\"," & ¬
				"\"account\":\"" & my jsonEscape(theAccount) & "\"" & ¬
				"}"
			set output to output & line & (ASCII character 10)
		on error errMsg number errNum
			-- Swallow single-note errors; emit a comment line the Swift
			-- side treats as a warning (lines not starting with '{').
			set output to output & ¬
				"# skipped note err=" & errNum & " msg=" & errMsg & ¬
				(ASCII character 10)
		end try
	end repeat
end tell

-- `osascript` writes this return value to stdout verbatim.
return output
