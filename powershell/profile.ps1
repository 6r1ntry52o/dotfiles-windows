# PowerShell profile, dot-sourced from $PROFILE by install.ps1.
# Keep this file ASCII: Windows PowerShell 5.1 reads BOM-less files as ANSI.

# Tell WezTerm the current directory on every prompt (OSC 7), so that new tabs
# and splits open where you are. PowerShell's cd does not change the process
# working directory, so WezTerm cannot see it otherwise.
if ($env:TERM_PROGRAM -eq 'WezTerm') {
    function prompt {
        $p = $executionContext.SessionState.Path.CurrentLocation
        $osc7 = ''
        if ($p.Provider.Name -eq 'FileSystem') {
            $esc = [char]27
            $path = $p.ProviderPath -replace '\\', '/'
            $osc7 = "$esc]7;file://${env:COMPUTERNAME}/$path$esc\"
        }
        "${osc7}PS $p$('>' * ($nestedPromptLevel + 1)) "
    }
}

# vi / vim / view open Neovim (only when nvim is installed).
# view is a function because a PowerShell alias cannot carry an argument.
if (Get-Command nvim -CommandType Application -ErrorAction SilentlyContinue) {
    Set-Alias -Name vi -Value nvim
    Set-Alias -Name vim -Value nvim
    function view { nvim -R @args }
}
