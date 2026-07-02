# =============================================================================
# UI.ps1 — TUI rendering engine
# Provides all terminal drawing functions: boxes, menus, progress bars, prompts.
# Uses ANSI escape codes for colour and cursor control — no external dependencies.
# Compatible with PowerShell 5.1 and 7+.
# =============================================================================

# ANSI escape character used to build colour/cursor sequences
$script:ESC = [char]27

# Colour definitions mapped to ANSI foreground codes.
# These are referenced throughout the module for consistent theming.
$script:Colours = @{
    Reset   = "$($script:ESC)[0m"
    White   = "$($script:ESC)[97m"
    Cyan    = "$($script:ESC)[96m"
    Green   = "$($script:ESC)[92m"
    Yellow  = "$($script:ESC)[93m"
    Red     = "$($script:ESC)[91m"
    Gray    = "$($script:ESC)[90m"
    Blue    = "$($script:ESC)[94m"
}

# ---------------------------------------------------------------------------
# Write-Colour
# Writes text to the console in the specified colour, then resets.
# Used by all other UI functions instead of Write-Host directly.
# ---------------------------------------------------------------------------
function Write-Colour {
    param(
        [string]$Text,
        [string]$Colour = 'White',
        [switch]$NoNewline
    )
    $code = $script:Colours[$Colour]
    if (-not $code) { $code = $script:Colours['White'] }

    if ($NoNewline) {
        Write-Host "$code$Text$($script:Colours['Reset'])" -NoNewline
    } else {
        Write-Host "$code$Text$($script:Colours['Reset'])"
    }
}

# ---------------------------------------------------------------------------
# Clear-Screen
# Clears the terminal and moves the cursor to the top-left.
# Used before drawing each new screen so previous content doesn't bleed through.
# ---------------------------------------------------------------------------
function Clear-Screen {
    # ANSI: clear screen + move cursor to position 1,1
    Write-Host "$($script:ESC)[2J$($script:ESC)[H" -NoNewline
}

# ---------------------------------------------------------------------------
# Write-Header
# Draws the standard double-line box header shown on every screen.
# Parameters:
#   Title     — main title text centred in the top bar
#   SubInfo   — optional key/value string shown in the second row (e.g. "ISO: foo.iso")
# ---------------------------------------------------------------------------
function Write-Header {
    param(
        [string]$Title = 'HYPER-V QUICK DEPLOY  v1.0',
        [string]$SubInfo = ''
    )

    # Box is 78 chars wide (76 inner + 2 border chars)
    $width = 76

    Write-Colour '╔' -Colour Cyan -NoNewline
    Write-Colour ('═' * $width) -Colour Cyan -NoNewline
    Write-Colour '╗' -Colour Cyan

    # Centre the title within the inner width
    $padded = $Title.PadLeft([math]::Floor(($width + $Title.Length) / 2)).PadRight($width)
    Write-Colour '║' -Colour Cyan -NoNewline
    Write-Colour $padded -Colour White -NoNewline
    Write-Colour '║' -Colour Cyan

    if ($SubInfo) {
        # Divider between title and sub-info rows
        Write-Colour '╠' -Colour Cyan -NoNewline
        Write-Colour ('═' * $width) -Colour Cyan -NoNewline
        Write-Colour '╣' -Colour Cyan

        # Truncate SubInfo if it would overflow the box
        $subContent = "  $SubInfo"
        if ($subContent.Length -gt $width) { $subContent = $subContent.Substring(0, $width - 3) + '...' }
        $subPadded = $subContent.PadRight($width)
        Write-Colour '║' -Colour Cyan -NoNewline
        Write-Colour $subPadded -Colour Gray -NoNewline
        Write-Colour '║' -Colour Cyan
    }

    Write-Colour '╚' -Colour Cyan -NoNewline
    Write-Colour ('═' * $width) -Colour Cyan -NoNewline
    Write-Colour '╝' -Colour Cyan
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Write-StatusHeader
# Draws the header in a specific status colour (green for success, red for error).
# Used on the success and error screens.
# Parameters:
#   Message — status line text (e.g. "VM Created Successfully")
#   Colour  — 'Green' or 'Red'
# ---------------------------------------------------------------------------
function Write-StatusHeader {
    param(
        [string]$Message,
        [string]$Colour = 'Green'
    )

    $width = 76

    Write-Colour '╔' -Colour $Colour -NoNewline
    Write-Colour ('═' * $width) -Colour $Colour -NoNewline
    Write-Colour '╗' -Colour $Colour

    $padded = "  $Message".PadRight($width)
    Write-Colour '║' -Colour $Colour -NoNewline
    Write-Colour $padded -Colour $Colour -NoNewline
    Write-Colour '║' -Colour $Colour

    Write-Colour '╠' -Colour $Colour -NoNewline
    Write-Colour ('═' * $width) -Colour $Colour -NoNewline
    Write-Colour '╣' -Colour $Colour
}

# ---------------------------------------------------------------------------
# Write-SummaryRow
# Writes a single key/value row inside a ║ ... ║ bordered box.
# Parameters:
#   Key     — left-hand label (padded to 16 chars)
#   Value   — right-hand value text
#   Colour  — optional colour override for the value (default White)
# ---------------------------------------------------------------------------
function Write-SummaryRow {
    param(
        [string]$Key,
        [string]$Value,
        [string]$Colour = 'White'
    )

    $width = 76
    $keyPad  = $Key.PadRight(16)
    $content = "  $keyPad$Value"
    $padded  = $content.PadRight($width)

    Write-Colour '║' -Colour Cyan -NoNewline
    Write-Colour $padded -Colour $Colour -NoNewline
    Write-Colour '║' -Colour Cyan
}

# ---------------------------------------------------------------------------
# Write-BoxDivider
# Draws a ╠═══╣ divider line inside an open box.
# ---------------------------------------------------------------------------
function Write-BoxDivider {
    param([string]$Colour = 'Cyan')
    $width = 76
    Write-Colour '╠' -Colour $Colour -NoNewline
    Write-Colour ('═' * $width) -Colour $Colour -NoNewline
    Write-Colour '╣' -Colour $Colour
}

# ---------------------------------------------------------------------------
# Write-BoxFooter
# Draws the ╚═══╝ closing line of a box.
# ---------------------------------------------------------------------------
function Write-BoxFooter {
    param([string]$Colour = 'Cyan')
    $width = 76
    Write-Colour '╚' -Colour $Colour -NoNewline
    Write-Colour ('═' * $width) -Colour $Colour -NoNewline
    Write-Colour '╝' -Colour $Colour
}

# ---------------------------------------------------------------------------
# Write-ActionBar
# Draws the ╠═══╣ divider followed by an action row and the ╚═══╝ footer.
# Parameters:
#   Actions — string describing the available key bindings, e.g. "[ C ] Create & Start"
# ---------------------------------------------------------------------------
function Write-ActionBar {
    param(
        [string]$Actions,
        [string]$Actions2 = ''
    )
    $width = 76
    Write-BoxDivider
    $padded = "  $Actions".PadRight($width)
    Write-Colour '║' -Colour Cyan -NoNewline
    Write-Colour $padded -Colour Yellow -NoNewline
    Write-Colour '║' -Colour Cyan
    if ($Actions2) {
        $padded2 = "  $Actions2".PadRight($width)
        Write-Colour '║' -Colour Cyan -NoNewline
        Write-Colour $padded2 -Colour Yellow -NoNewline
        Write-Colour '║' -Colour Cyan
    }
    Write-BoxFooter
}

# ---------------------------------------------------------------------------
# Select-FromList
# Interactive arrow-key menu. Returns the selected item, or $null if Esc pressed.
# Redraws the full screen on every keypress to avoid cursor-math artifacts
# that occur when item text wraps across terminal lines.
# Parameters:
#   Items        -- array of strings to display
#   DefaultIndex -- index to pre-highlight (default 0)
#   Title        -- screen title passed to Write-Header on each redraw
#   SubInfo      -- optional sub-info line for Write-Header
# ---------------------------------------------------------------------------
function Select-FromList {
    param(
        [string[]]$Items,
        [int]$DefaultIndex = 0,
        [string]$Title     = '',
        [string]$SubInfo   = ''
    )

    $maxVisible = 8
    # Inner width matches the header box (76 inner + 2 borders = 78 total)
    $innerWidth = 74
    # Max chars for item text: inner width minus the 4-char selection prefix '  > '
    $maxContent = $innerWidth - 4

    $selectedIndex = $DefaultIndex
    $scrollOffset  = 0

    if ($selectedIndex -ge $Items.Count) { $selectedIndex = 0 }

    [Console]::CursorVisible = $false

    try {
        while ($true) {
            # Adjust scroll window so the selected item is always visible
            if ($selectedIndex -lt $scrollOffset) {
                $scrollOffset = $selectedIndex
            } elseif ($selectedIndex -ge ($scrollOffset + $maxVisible)) {
                $scrollOffset = $selectedIndex - $maxVisible + 1
            }

            $visibleItems   = $Items[$scrollOffset..([math]::Min($scrollOffset + $maxVisible - 1, $Items.Count - 1))]
            $showScrollUp   = $scrollOffset -gt 0
            $showScrollDown = ($scrollOffset + $maxVisible) -lt $Items.Count

            # Full clear + header redraw on every keypress.
            # This eliminates all cursor arithmetic and prevents ghost artifacts
            # caused by filenames that are wider than the list box.
            Clear-Screen
            if ($Title) { Write-Header -Title $Title -SubInfo $SubInfo }

            Write-Host ''
            Write-Colour '  ┌' -Colour Gray -NoNewline
            Write-Colour ('─' * $innerWidth) -Colour Gray -NoNewline
            Write-Colour '┐' -Colour Gray

            if ($showScrollUp) {
                $indicator = ('  ^ more' + (' ' * ($innerWidth - 8)))
                Write-Colour '  │' -Colour Gray -NoNewline
                Write-Colour $indicator -Colour Yellow -NoNewline
                Write-Colour '│' -Colour Gray
            }

            foreach ($i in 0..($visibleItems.Count - 1)) {
                $absoluteIndex = $scrollOffset + $i
                $isSelected    = ($absoluteIndex -eq $selectedIndex)

                # Truncate names longer than the box so the terminal never wraps.
                # Wrapping adds phantom lines that break any future cursor positioning.
                $name = $visibleItems[$i]
                if ($name.Length -gt $maxContent) {
                    $name = $name.Substring(0, $maxContent - 3) + '...'
                }

                Write-Colour '  │' -Colour Gray -NoNewline

                if ($isSelected) {
                    $line = "  > $name".PadRight($innerWidth)
                    Write-Colour $line -Colour Cyan -NoNewline
                } else {
                    $line = "    $name".PadRight($innerWidth)
                    Write-Colour $line -Colour White -NoNewline
                }

                Write-Colour '│' -Colour Gray
            }

            if ($showScrollDown) {
                $indicator = ('  v more' + (' ' * ($innerWidth - 8)))
                Write-Colour '  │' -Colour Gray -NoNewline
                Write-Colour $indicator -Colour Yellow -NoNewline
                Write-Colour '│' -Colour Gray
            }

            Write-Colour '  └' -Colour Gray -NoNewline
            Write-Colour ('─' * $innerWidth) -Colour Gray -NoNewline
            Write-Colour '┘' -Colour Gray
            Write-Host ''
            Write-Colour '  [ Up/Dn Navigate ]  [ Enter Select ]  [ Esc Back/Quit ]' -Colour Gray
            Write-Host ''

            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

            switch ($key.VirtualKeyCode) {
                38 { $selectedIndex = if ($selectedIndex -gt 0) { $selectedIndex - 1 } else { $Items.Count - 1 } }
                40 { $selectedIndex = if ($selectedIndex -lt ($Items.Count - 1)) { $selectedIndex + 1 } else { 0 } }
                13 { return $Items[$selectedIndex] }
                27 { return $null }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

# ---------------------------------------------------------------------------
# Read-TextInput
# Displays a prompt and reads a line of text from the user.
# Pre-fills a default value which the user can accept or overwrite.
# Parameters:
#   Prompt   — label shown above the input line
#   Default  — pre-filled value (shown in the input field)
# ---------------------------------------------------------------------------
function Read-TextInput {
    param(
        [string]$Prompt,
        [string]$Default = ''
    )

    Write-Host ''
    Write-Colour "  $Prompt" -Colour White
    Write-Colour '  > ' -Colour Cyan -NoNewline

    # Show the default in gray so the user knows they can just press Enter
    if ($Default) {
        Write-Colour $Default -Colour Gray -NoNewline
        # Move cursor back to start of the default text so typing replaces it
        Write-Host "$($script:ESC)[$($Default.Length)D" -NoNewline
    }

    $input = Read-Host
    # If the user pressed Enter without typing, keep the default
    if ([string]::IsNullOrWhiteSpace($input)) { $Default } else { $input }
}

# ---------------------------------------------------------------------------
# Write-ProgressScreen
# Draws the VM-creation progress screen with a step checklist and progress bar.
# Parameters:
#   VMName      — name of the VM being created (shown in the header)
#   Steps       — ordered array of step label strings
#   ActiveIndex — index of the currently running step (0-based)
# ---------------------------------------------------------------------------
function Write-ProgressScreen {
    param(
        [string]  $VMName,
        [string[]]$Steps,
        [int]     $ActiveIndex
    )

    Clear-Screen
    Write-Header -Title "Creating VM: $VMName"

    foreach ($i in 0..($Steps.Count - 1)) {
        if ($i -lt $ActiveIndex) {
            # Completed step — green
            Write-SummaryRow -Key '' -Value "[+] $($Steps[$i])" -Colour Green
        } elseif ($i -eq $ActiveIndex) {
            # Active step — cyan with ellipsis
            Write-SummaryRow -Key '' -Value "[>] $($Steps[$i])  ..." -Colour Cyan
        } else {
            # Pending step — muted
            Write-SummaryRow -Key '' -Value "  $($Steps[$i])" -Colour Gray
        }
    }

    # Calculate progress percentage based on completed steps
    $pct      = [math]::Round(($ActiveIndex / $Steps.Count) * 100)
    $barWidth = 72   # inner width of the progress bar
    $filled   = [math]::Round($barWidth * $pct / 100)
    $empty    = $barWidth - $filled

    Write-BoxDivider
    Write-Colour '║' -Colour Cyan -NoNewline
    Write-Colour '  [' -Colour Gray -NoNewline
    Write-Colour ('█' * $filled) -Colour Cyan -NoNewline
    Write-Colour (' ' * $empty) -Colour Gray -NoNewline
    Write-Colour "]  $("$pct%".PadLeft(4)) " -Colour Gray -NoNewline
    Write-Colour '║' -Colour Cyan
    Write-BoxFooter
}

# ---------------------------------------------------------------------------
# Write-Notification
# Shows a full-screen notification box (used for errors and warnings).
# Parameters:
#   Title   — short label for the header bar (e.g. "Pre-flight check failed")
#   Message — plain-English explanation shown below the box
#   Hint    — optional fix hint shown in muted colour
#   Colour  — 'Red' for errors, 'Yellow' for warnings (default Red)
# ---------------------------------------------------------------------------
function Write-Notification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Hint   = '',
        [string]$Colour = 'Red'
    )

    Clear-Screen
    Write-StatusHeader -Message $Title -Colour $Colour
    Write-BoxFooter -Colour $Colour
    Write-Host ''
    Write-Colour "  $Message" -Colour White
    Write-Host ''

    if ($Hint) {
        Write-Colour "  $Hint" -Colour Gray
        Write-Host ''
    }

    Write-Colour '  [ Press any key to continue ]' -Colour Gray
    $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | Out-Null
}
