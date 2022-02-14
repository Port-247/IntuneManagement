<#
.SYNOPSIS
Core UI and Settings fatures for the CloudAPIPowerShellManager solution 

.DESCRIPTION
This module handles the WPF UI

.NOTES
  Author:         Mikael Karlsson
#>

function Get-ModuleVersion
{
    '3.3.2'
}

function Start-CoreApp
{
    param($View)

    if(-not $global:defaultGlobalVariables)
    {
        $global:defaultGlobalVariables = Get-Variable -Scope Global
    }

    $global:useDefaultFolderDialog = $false
    $global:WindowsAPICodePackLoaded = $false

    $global:loadedModules = @()
    $global:viewObjects = @()
    $script:LogItems = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

    $global:AppRootFolder = $PSScriptRoot

    # Load all modules in the Modules folder
    $global:modulesPath = [IO.Path]::GetDirectoryName($PSCommandPath) + "\Extensions"

    Add-DefaultSettings

    if($global:UseJSonSettings -eq $true)
    {
        Initialize-JsonSettings
    }

    if($global:UseJSonSettings -eq $false)
    {
        Write-Log "Use settings in registry"
    }    

    Write-Log "#####################################################################################"
    Write-Log "Application started"
    Write-Log "#####################################################################################"

    if(Test-Path $global:modulesPath)
    { 
        Import-AllModules
    }
    else
    {
        Write-Warning "Extensions folder $($global:modulesPath) not found. Aborting..." 3
        exit 1
    }

    Initialize-Settings
    $global:currentViewObject = $null
    $global:FirstTimeRunning = ((Get-Setting "" "FirstTimeRunning" "true") -eq "true")
    $global:MainAppStarted = $false

    $global:txtSplashText.Text = "Initialize views"
    [System.Windows.Forms.Application]::DoEvents()

    Invoke-ModuleFunction "Invoke-InitializeModule"

    #Add menu group and items
    $script:LogViewObject = (New-Object PSObject -Property @{ 
        Title = "Log"
        Description = "View log items"
        ID = "CoreLog"
        HideMenu = $true
        Activating = { Show-LogView }
        Permissions = @()
        ViewPanel = $null
    })

    Add-ViewObject $script:LogViewObject

    #This will load the main window
    $global:txtSplashText.Text = "Load main window"
    [System.Windows.Forms.Application]::DoEvents()
    Get-MainWindow

    if($global:window)
    {
        $global:txtSplashText.Text = "Open default view"
        [System.Windows.Forms.Application]::DoEvents()

        Show-View $View

        Invoke-ModuleFunction "Invoke-ShowMainWindow"

        $global:txtSplashText.Text = "Open main window"
        [System.Windows.Forms.Application]::DoEvents()
        $global:window.ShowDialog() | Out-Null
    }
}

function Import-AllModules
{
    foreach($file in (Get-Item -path "$($global:modulesPath)\*.psm1"))
    {      
        $fileName = [IO.Path]::GetFileName($file) 
        if($skipModules -contains $fileName) { Write-Warning "Module $fileName excluded"; continue; }

        $global:txtSplashText.Text = "Import module $fileName"
        [System.Windows.Forms.Application]::DoEvents()

        $module = Import-Module $file -PassThru -Force -Global -ErrorAction SilentlyContinue
        if($module)
        {
            $global:loadedModules += $module
            Write-Host "Module $($module.Name) loaded successfully"
        }
        else
        {
            Write-Warning "Failed to load module $file"
        }
    }
}

#region Log functions
function Write-Log
{
    param($Text, $type = 1)

    if($script:logFailed -eq $true) { return }

    if(-not $global:logFile) { $global:logFile = Get-SettingValue "LogFile" ([IO.Path]::Combine($global:AppRootFolder,"CloudAPIPowerShellManagement.log")) }

    if(-not $global:logFileMaxSize) { [Int64]$global:logFileMaxSize =  Get-SettingValue "LogFileSize" 1024; $global:logFileMaxSize = $global:logFileMaxSize * 1kb }

    $fi = [IO.FileInfo]$global:logFile

    if($fi.Length -gt $global:logFileMaxSize)
    {
        # Larger than max size. Rename current to .bak
        # Delete current .bak if it exists        
        $bakFile = ($fi.DirectoryName + "\" + $fi.BaseName + ".lo_")
        if([IO.File]::Exists($bakFile))
        {
            try
            {
                [IO.File]::Delete($bakFile)
            }
            catch { }
        }
        try
        {
            $fi.MoveTo($bakFile)
        }
        catch { }
    }

    try
    {
        $logPath = [IO.Path]::GetDirectoryName($global:logFile)        
        if(-not (Test-Path $logPath)) { mkdir -Path $logPath -Force -ErrorAction SilentlyContinue | Out-Null }
    }
    catch 
    {
        $script:logFailed = $true
        return
    }

    $date = Get-Date
    
    if($global:PSCommandPath)
    {
        $fileObj = [System.IO.FileInfo]$global:PSCommandPath
    }
    else
    {
        $fileObj = [System.IO.FileInfo]$PSCommandPath
    }

    $timeStr = "$($date.ToString(""HH"")):$($date.ToString(""mm"")):$($date.ToString(""ss"")).000+000"
    $dateStr = "$($date.ToString(""MM""))-$($date.ToString(""dd""))-$($date.ToString(""yyyy""))"    
    $logOut = "<![LOG[$Text]LOG]!><time=""$timeStr"" date=""$dateStr"" component=""$($fileObj.BaseName)"" context="""" type=""$type"" thread=""$PID"" file=""$($fileObj.BaseName)"">"

    if($type -eq 2)
    {
        Write-Warning $Text
        $typeStr = "Error"
    }
    elseif($type -eq 3)
    {
        $host.ui.WriteErrorLine($Text)
        $typeStr = "Warning"
    }
    else
    {
        write-host $Text
        $typeStr = "Info"
    }

    $script:LogItems.Add([PSCustomObject]@{
        ID = ($script:LogItems.Count + 1)
        DateTime = $date
        Type = $type
        TypeText = $typeStr
        Text = $Text
    })

    try
    {    
        out-file -filePath $global:logFile -append -encoding "ASCII" -inputObject $logOut
    }
    catch { }
}

function Write-LogDebug
{
    param($Text, $type = 1)

    if($global:Debug)
    {
        Write-Log ("Debug: " + $text) $type
    }
}

function Write-LogError
{
    param($Text, $Exception)

    if($Text -and $Exception.message)
    {
        $Text += " Exception: $($Exception.Message)"
    }

    Write-Log $Text 3
}

function Write-Status
{
    param($Text, [switch]$SkipLog, [switch]$Block, [switch]$Force)
    
    if(-not $text) { $global:BlockStatusUpdates = $false }    
    elseif($global:BlockStatusUpdates -eq $true -and $Force -ne $true) { return }
    elseif($Block -eq $true) { $global:BlockStatusUpdates = $true }

    $global:txtInfo.Content = $Text
    if($text)
    {
        $global:grdStatus.Visibility = "Visible"
        if($SkipLog -ne $true) { Write-Log $text }
    }
    else
    {
        $global:grdStatus.Visibility = "Collapsed"
    }

    [System.Windows.Forms.Application]::DoEvents()
}

#endregion

#region Popup
function Show-Popup
{
    param($popup)

    if(-not $global:grdPopup -or -not $global:cvsPopup) { return }

    $global:cvsPopup.AddChild($popup) | Out-Null
    $global:grdPopup.Visibility = "Visible"

    [System.Windows.Forms.Application]::DoEvents()
}

function Hide-Popup
{
    if(-not $global:grdPopup -or -not $global:cvsPopup) { return }
    $global:cvsPopup.Children.Clear()
    $global:grdPopup.Visibility = "Collapsed"
    [System.Windows.Forms.Application]::DoEvents()
}
#endregion

#region Xaml functions

function Set-XamlProperty
{
    param($xamlObj, $controlName, $propertyName, $value)

    $obj = $xamlObj.FindName($controlName)

    try
    {
        if($obj)
        {
            $obj."$propertyName" = $value
        }
        else 
        {
            Write-Log "Could not find object with name $controlName" 3    
        }
        }
    catch 
    {
        Write-LogError "Failed to set Xaml property value. Control: $controlName. Property: $propertyName. Error:" $_.Exception
    }
}

function Get-XamlProperty
{
    param($xamlObj, $controlName, $propertyName, $defaultValue)

    $obj = $xamlObj.FindName($controlName)

    try
    {
        if($obj)
        {
            return (?? $obj."$propertyName" $null)
        }
        else 
        {
            Write-Log "Could not find object with name $controlName" 3    
        }
        }
    catch 
    {
        Write-LogError "Failed to set Xaml property value. Control: $controlName. Property: $propertyName. Error:" $_.Exception
    }
}

function Add-XamlEvent
{
    param($xamlObj, $controlName, $eventName, $scriptBlock)

    try {
        $obj = $xamlObj.FindName($controlName)
        if($obj)
        {
            $obj."$eventName"($scriptBlock)
        }
        else 
        {
            Write-Log "Failed to add Xaml event $eventName to $controlName. Control not found" 3
        }
    }
    catch 
    {
        Write-LogError "Failed to add Xaml event $eventName to $controlName. Error:" $_.Exception
    }
}

function Add-XamlVariables
{
    param($xaml, $obj)
  
    # Generate a global variable for each object with Name property set
    # Ref: https://learn-powershell.net/2014/08/10/powershell-and-wpf-radio-button/
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
        Write-LogDebug "Add global variable $($_.Name)"
        New-Variable  -Name $_.Name -Value $obj.FindName($_.Name) -Force -Scope Global
    }
}

function Get-XamlObject
{
    param($fileName, [switch]$AddVariables)

    if(([IO.File]::Exists($fileName)))
    {
        try 
        {
            [xml]$xaml = Get-Content $fileName
            
            $xamlObj = ([Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml)))

            if($xamlObj -and $AddVariables -eq $true)
            {
                Add-XamlVariables $xaml $xamlObj
            }
            return $xamlObj
        }
        catch
        {
            Write-LogError "Failed to load Xaml file $fileName. Error:" $_.Exception
        }
    }
    else
    {
        Write-Log "Failed to open Xaml file. File not found: $fileName"
    }
}

function Invoke-RegisterName
{
    param($parent, $name, $registerTo)

    try
    {
        $control = $parent.FindName($name)
        if($control)
        {
            $registerTo.RegisterName($name, $control)
        }
    }
    catch    
    {
        Write-LogError "Failed to register $name" $_.Exception
    }
}

#endregion

#region Dialogs

function Show-AboutDialog
{
    $script:dlgAbout = Get-XamlObject ($global:AppRootFolder + "\Xaml\AboutDialog.xaml")
    if(-not $script:dlgAbout) { return }

    $loadedItems = @()
    $externalModules = @("MSAL.PS","Az.Account")
    $externalAssemblies = @("Microsoft.Identity.Client.dll")

    foreach($module in (((Get-Module | Where-Object { $_.ModuleBase -like "$($global:AppRootFolder)*" -or $_.Name -in $externalModules }))))
    {
        $ver = $module.Version
        if($module.Version.Major -eq 0 -and $module.Version.Minor -eq 0)
        {
            $cmd = $module.ExportedFunctions["Get-ModuleVersion"]
            if($cmd)
            {
                $tmpVer = Invoke-Command -ScriptBlock $cmd.ScriptBlock
                $ver = ?? $tmpVer $ver
            }     
        }

        $loadedItems += (New-Object PSObject -Property @{
            Name = $module.Name
            Version = $ver
            Type = "PSModule"
        })
    }

    $assms = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where { $_.GlobalAssemblyCache -eq $false -and [String]::IsNullOrEmpty($_.Location) -eq $false }
    foreach($assmName in $externalAssemblies)
    {
        $assmObjs = $assms | Where { $_.Location -like "*\$($assmName)" }
        foreach($assmObj in $assmObjs)
        {
            try 
            {
                $fi = [IO.FileInfo]"$($assmObj.Location)"
                $loadedItems += (New-Object PSObject -Property @{
                    Name = $fi.Name
                    Version = $fi.VersionInfo.FileVersion
                    Type = "Assembly"
                })
            }
            catch {}
        }
    }

    Set-XamlProperty $script:dlgAbout "txtTitle" "Text" "CloudAPIPowerShellManagement"
    Set-XamlProperty $script:dlgAbout "txtViewTitle" "Text" ("Current view: " + $global:currentViewObject.ViewInfo.Title)
    if($global:currentViewObject.ViewInfo.Description)
    {
        Set-XamlProperty $script:dlgAbout "txtViewDescription" "Text" $global:currentViewObject.ViewInfo.Description
    }

    Set-XamlProperty $script:dlgAbout "lstModules" "ItemsSource" $loadedItems

    Add-XamlEvent $script:dlgAbout "linkSource" "Add_RequestNavigate" ({ [System.Diagnostics.Process]::Start($_.Uri.AbsoluteUri); $_.Handled = $true })

    Show-ModalForm "About" $script:dlgAbout 
}

function Show-UpdatesDialog
{
    $script:dlgUpdates = Get-XamlObject ($global:AppRootFolder + "\Xaml\UpdatesDialog.xaml")
    if(-not $script:dlgUpdates) { return }

    Write-Status "Getting Release Notes Information"

    Add-XamlEvent $script:dlgUpdates "btnClose" "add_click" {
        $script:dlgUpdates = $null
        Show-ModalObject 
    }    

    #Get-Module | Where Name -eq "Core"
    $fileContent = Get-Content -Raw -Path ($global:AppRootFolder + "\ReleaseNotes.md")
    try
    {
        $tmp = $fileContent.Replace("`r`n","`n")
        $mystring = ("blob $($tmp.Length)`0" + $tmp)
        $mystream = [IO.MemoryStream]::new([byte[]][char[]]$mystring)
        $curHash = Get-FileHash -InputStream $mystream -Algorithm SHA1
    }
    finally
    {
        if($mystream) { $mystream.Dispose() }
    }

    <#
    $latest = Invoke-RestMethod "https://api.github.com/repos/Micke-K/IntuneManagement/releases/latest"
    if($latest)
    {

    }
    #>

    $content = Invoke-RestMethod "https://api.github.com/repos/Micke-K/IntuneManagement/contents/ReleaseNotes.md"
    if($content)
    {
        $txt = [System.Text.Encoding]::UTF8.GetString(([System.Convert]::FromBase64String($content.content)))
        Set-XamlProperty $script:dlgUpdates "txtReleaseNotes" "Text" $txt

        if($content.sha -ne $curHash.Hash)
        {
            # ReleaseNotes.md not matching
            Set-XamlProperty $script:dlgUpdates "tabLocalReleaseNotes" "Visibility" "Visible"
            Set-XamlProperty $script:dlgUpdates "txtReleaseNotes" "Text" $fileContent
            Set-XamlProperty $script:dlgUpdates "txtReleaseNotesMatch" "Visibility" "Collapsed"
        }
        else
        {
            Set-XamlProperty $script:dlgUpdates "txtReleaseNotesNoMatch" "Visibility" "Collapsed"
            Set-XamlProperty $script:dlgUpdates "tabLocalReleaseNotes" "Visibility" "Collapsed"
        }
    }

    Write-Status ""

    Show-ModalForm "Release Notes" $script:dlgUpdates -HideButtons
}

function Show-InputDialog
{
    param(
        $FormTitle = "Input",
        $FormText,
        $DefaultValue)

    $script:inputBox = Get-XamlObject ($global:AppRootFolder + "\Xaml\InputDialog.xaml")
    if(-not $script:inputBox) { return }
    
    $script:inputBox.Title = $FormTitle

    Set-XamlProperty $script:inputBox "txtLabel" "Content" $FormText
    Set-XamlProperty $script:inputBox "txtValue" "Text" $DefaultValue

    $script:txtValue = $script:inputBox.FindName("txtValue")

    Add-XamlEvent $script:inputBox "btnOk" "Add_Click" ({ $script:inputBox.Close() })
    Add-XamlEvent $script:inputBox "btnCancel" "Add_Click" ({ $script:txtValue.Text ="";$script:inputBox.Close() })

    $inputBox.Add_ContentRendered({
        $script:txtValue.SelectAll();
        $script:txtValue.Focus();
    })

    $inputBox.ShowDialog() | Out-null

    return $script:txtValue.Text
}

function Show-ModalForm
{
    param(
        $FormTitle = "",
        $formObject,
        [switch]$HideButtons)
    
    $xamlStr =  Get-Content ($global:AppRootFolder + "\Xaml\ModalForm.xaml")

    $modalForm = [Windows.Markup.XamlReader]::Parse($xamlStr)

    if($HideButtons -eq $true)
    {
        Set-XamlProperty $modalForm "spButtons" "Visibility" "Collapsed"
    }
    else 
    {    
        Add-XamlEvent $modalForm "btnClose" "Add_Click" ({
            Show-ModalObject
        })
    }

    Set-XamlProperty $modalForm "txtTitle" "Text" $FormTitle

    $grdModalContainer = $modalForm.FindName("grdModalContainer")
    if($grdModalContainer -and $formObject)
    {
        $formObject.SetValue([System.Windows.Controls.Grid]::RowProperty,1)
        $grdModalContainer.Children.Add($formObject) | Out-Null
    }
    Show-ModalObject $modalForm
}
function Show-ModalObject
{
    param( $obj )
        
    if($obj)
    {       
        $obj.SetValue([System.Windows.Controls.Grid]::RowProperty,1)
        $obj.SetValue([System.Windows.Controls.Grid]::ColumnProperty,1)
        $global:grdModal.Children.Add($obj) | Out-Null
        $global:grdModal.Visibility = "Visible"
    }
    else
    {
        $global:grdModal.Children.Clear()
        $global:grdModal.Visibility = "Collapsed"
    }

    [System.Windows.Forms.Application]::DoEvents()
}
#endregion

#region Controls
function Show-AuthenticationInfo
{
    if($global:grdMenu)
    {
        $global:txtSplashText.Text = "Get profile picture"
        [System.Windows.Forms.Application]::DoEvents()

        $authenticationProvider = $global:currentViewObject.ViewInfo.Authentication
        if($global:grdMenu.Children[-1].Tag -eq "ProfilePicture")
        {
            $global:grdMenu.Children.Remove($global:grdMenu.Children[-1])
        }

        if($authenticationProvider.ProfilePicture)
        {
            $profileObj = & $authenticationProvider.ProfilePicture -Size 24 -Fontsize 12 -Popup -AuthenticationProvider $authenticationProvider
            if($profileObj)
            {
                $profileObj.Tag = "ProfilePicture"
                $profileObj.SetValue([System.Windows.Controls.Grid]::ColumnProperty,1) | Out-Null
                $global:grdMenu.Children.Add($profileObj) | Out-Null
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
}
#endregion

#region Generic functions
function Invoke-Coalesce ($value, $default)
{    
    # Use IsNullOrEmpty instead of -not
    if ([String]::IsNullOrEmpty($value)) { $value = $default }

    return $value
}

function Invoke-IfTrue ($expression, $valueIfTrue, $valueIfFalse)
{        
    if ($expression) { return $valueIfTrue }
    else { return $valueIfFalse }
}

function Set-ObjectGrid
{
    param( $obj )
        
    if($obj)
    {       
        $global:grdObject.Children.Add($obj)
        $global:grdObject.Visibility = "Visible"
    }
    else
    {
        $global:grdObject.Children.Clear()
        $global:grdObject.Visibility = "Collapsed"
    }

    [System.Windows.Forms.Application]::DoEvents()
}

function Remove-InvalidFileNameChars
{
  param($Name)

  $re = "[{0}]" -f [RegEx]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))

  $Name = $Name -replace $re


  return $Name
}

function Remove-ObjectProperty
{
    param($obj, $property)

    if(-not $obj -or -not $property) { return }

    if(($obj | Get-Member -MemberType NoteProperty -Name $property))
    {
        $obj.PSObject.Properties.Remove($property)
    }
}

function Get-Folder
{
    param($path = $env:temp, $title = "Select a directory")
    
    if($global:useDefaultFolderDialog -ne $true)
    {
        try
        {
            if($global:WindowsAPICodePackLoaded -eq $false)
            {
                $apiCodec = Join-Path $global:AppRootFolder "Microsoft.WindowsAPICodePack.Shell.dll"
                if([IO.File]::Exists($apiCodec))
                {
                    Add-Type -Path $apiCodec | Out-Null                    
                    $global:WindowsAPICodePackLoaded = $true
                }
                else
                {
                    Write-Log "Could not find Microsoft.WindowsAPICodePack.Shell.dll" 2
                }
            }
            $dlgCOFD = New-Object Microsoft.WindowsAPICodePack.Dialogs.CommonOpenFileDialog
        }
        catch 
        {
            Write-LogError "Failed to load Microsoft.WindowsAPICodePack.Shell.dll. Verify that the .Net 3.5 feature is enabled" $_.Exception  
        }
    }

    if($dlgCOFD -and $global:useDefaultFolderDialog -ne $true)
    {
        $dlgCOFD.EnsureReadOnly = $true
        $dlgCOFD.IsFolderPicker = $true
        $dlgCOFD.AllowNonFileSystemItems = $false
        $dlgCOFD.Multiselect = $false
        $dlgCOFD.Title = $title
        
        if($path -and (Test-Path $path))
        {
            $dlgCOFD.InitialDirectory = $path
        }
        if($dlgCOFD.ShowDialog($window) = [Microsoft.WindowsAPICodePack.Dialogs.CommonFileDialogResult]::Ok)
        {
            $dlgCofd.FileName            
        }
    }
    else
    {
        $global:useDefaultFolderDialog = $true
        [Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
        [System.Windows.Forms.Application]::EnableVisualStyles()
        $dlgFBD = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlgFBD.SelectedPath = "C:\"
        $dlgFBD.ShowNewFolderButton = $false
        $dlgFBD.Description = $title
        if($dlgFBD.ShowDialog() -eq "OK")
        {
            $dlgFBD.SelectedPath
        }        
        $dlgFBD.Dispose()
    }
}
function Remove-Property 
{
    param($obj, $prop)

    if(-not $prop) { return }

    if(($obj | GM -MemberType NoteProperty -Name $prop))
    {
        Write-LogDebug "Remove property $prop"
        $obj.PSObject.Properties.Remove($prop) | Out-Null
    }
}

function Get-GridCheckboxColumn
{
    param($bindingProperty = "IsSelected", [scriptblock]$scriptBlock)

    $binding = [System.Windows.Data.Binding]::new($bindingProperty)
    $binding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::PropertyChanged
    $column = [System.Windows.Controls.DataGridTemplateColumn]::new()
    $fef = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.CheckBox])
    $binding.Mode = [System.Windows.Data.BindingMode]::TwoWay
    $fef.SetValue([System.Windows.Controls.CheckBox]::IsCheckedProperty,$binding)
    if($null -ne $scriptBlock)
    {
        [System.Windows.RoutedEventHandler]$checkedEventHandler = $scriptBlock
        $fef.AddHandler([System.Windows.Controls.CheckBox]::CheckedEvent, $checkedEventHandler) 
    }
    $dt = [System.Windows.DataTemplate]::new()
    $dt.VisualTree = $fef
    $column.CellTemplate = $dt
    $header = [System.Windows.Controls.CheckBox]::new()
    $header.Margin = [System.Windows.Thickness]::new(-4,0,0,0) # Align header checkbox with the row checkboxes
    $header.ToolTip = "Select/deselect all items"
    $column.Header = $header
    if($null -ne $scriptBlock)
    {
        #$header.add_click($scriptBlock)
    }

    $column        
}

function Expand-FileName
{
    param($fileName)

    [Environment]::SetEnvironmentVariable("Date",(Get-Date).ToString("yyyy-MM-dd"),[System.EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable("DateTime",(Get-Date).ToString("yyyyMMdd-HHmm"),[System.EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable("Organization",$global:Organization.displayName,[System.EnvironmentVariableTarget]::Process)
    
    $fileName = [Environment]::ExpandEnvironmentVariables($fileName)

    foreach($tmpFolder in ([System.Enum]::GetNames([System.Environment+SpecialFolder])))
    {
        $fileName = $fileName -replace "%$($tmpFolder)%",([Environment]::GetFolderPath($tmpFolder))
    }

    [Environment]::SetEnvironmentVariable("Date",$null,[System.EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable("DateTime",$null,[System.EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable("Organization",$null,[System.EnvironmentVariableTarget]::Process)
    
    $fileName
}

#endregion

#region Save/Read Settings functions
########################################################################
#
# Save/Read Settings
#
########################################################################
function Initialize-Settings
{
    param([switch]$Updated)

    $global:Debug = Get-SettingValue "Debug"
    $global:logFile = $null
    $global:logFileMaxSize = $null
    
    if($Updated -eq $true)
    {
        Invoke-ModuleFunction "Invoke-SettingsUpdated"
    }
}

function Initialize-JsonSettings
{
    if(-not $global:JSonSettingFile)
    {
        $global:JSonSettingFile = "$($env:LOCALAPPDATA)\CloudAPIPowerShellManagement\Settings.json"
        $fi = [IO.FileInfo]$global:JSonSettingFile
        if($fi.Exists -eq $false)
        {
            Export-Settings $fi.FullName
        }        
    }
    else 
    {
        $fi = [IO.FileInfo]$global:JSonSettingFile
        if($fi.Exists -eq $false)
        {
            try
            {                
                Write-Host "Settings file $($fi.FullName) does not exist. Create empty settings"
                @{} | ConvertTo-Json | Out-File -FilePath $global:JSonSettingFile -Force -Encoding utf8
            }
            catch
            {
                Clear-JsonSettingsValues
                Write-LogError "Failed to create json setting file $($fi.FullName). Veirfy write access. Registry settings will be used." $_.Exception
            }
        }
    }

    $fi = [IO.FileInfo]$global:JSonSettingFile
    if($fi.Exists -eq $true)
    {
        try
        {
            $global:JsonSettingsObj = (ConvertFrom-Json (Get-Content -Path $fi.FullName -Raw))
            Write-Log "Use json settings file: $($fi.FullName)"
            return
        }
        catch
        {            
            Clear-JsonSettingsValues
            Write-LogError "Failed to read json setting file $($fi.FullName). Registry settings will be used." $_.Exception
        }
    }
    else
    {
        Clear-JsonSettingsValues
        Write-LogError "Could not find json setting file $($fi.FullName). Registry settings will be used"
    }
    
}

function Clear-JsonSettingsValues
{
    # Failed - Revert back to reg settings
    $global:JsonSettingsObj =  $null
    $global:JSonSettingFile = $null
    $global:UseJSonSettings = $false
}

function Save-Setting
{
    param($SubPath = "", $Key = "", $Value, $Type = "String")

    if($global:JsonSettingsObj -and $global:JSonSettingFile)
    {
        if($SubPath)
        {        
            $arrParts = $SubPath.TrimEnd(@('/','\')).Split(@('/','\'))
        }
        else
        {
            $arrParts = @()
        }

        $parentSetting = $global:JsonSettingsObj

        foreach($part in $arrParts)
        {
            if(-not $part.Trim()) { continue }

            if(($parentSetting.PSObject.Properties | Where Name -eq $part))
            {
                $parentSetting = $parentSetting.$part
            }
            else
            {
                $parentSetting | Add-Member -MemberType NoteProperty -Name $part -Value ([PSCustomObject]@{})
                $parentSetting = $parentSetting.$part
            }
        }

        try
        {
            if($null -eq $Value)
            {
                if(($parentSetting.PSObject.Properties | Where Name -eq $Key))
                {
                    $parentSetting.PSObject.Properties.Remove($Key) | Out-Null
                }
            }
            else
            {
                if($Type -eq "String" -and $null -ne $value)
                {
                    $Value = $value.ToString()
                }
                elseif($Type -eq "DWord" -and $null -ne $Value)
                {
                    $Value = [Int]::Parse($Value)
                }

                if(-not ($parentSetting.PSObject.Properties | Where Name -eq $Key))
                {
                    $parentSetting | Add-Member -MemberType NoteProperty -Name $Key -Value $Value 
                }
                else
                {
                    $parentSetting.$Key = $Value
                }
            }

            $global:JsonSettingsObj | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $global:JSonSettingFile -Force -Encoding utf8
        }
        catch
        {
            Write-LogError "Failed to save json setting value $Key" $_.Exception
        }
    }
    else
    {
        $regPath = Get-RegPath $SubPath
        if((Test-Path $regPath) -eq  $false)
        {
            New-Item (Get-RegPath $SubPath) -Force -ErrorAction SilentlyContinue | Out-Null
        }
     
        New-ItemProperty -Path $regPath -Name $Key -Value $Value -Type $Type -Force | Out-Null
    }
}

function Get-Setting
{    
    param($SubPath = "", $Key = "", $defautValue)

    if(-not $key)
    {
        return
    }

    $val = $null

    if($global:JsonSettingsObj)
    {
        try
        {
            if($SubPath)
            {
                $arrParts = $SubPath.TrimEnd(@('/','\')).Split(@('/','\'))
            }
            else
            {
                $arrParts = @()
            }

            $parentSetting = $global:JsonSettingsObj
            $found = $true

            foreach($part in $arrParts)
            {
                if(($parentSetting.PSObject.Properties | Where Name -eq $part))
                {
                    $parentSetting = $parentSetting.$part
                }
                else
                {     
                    $found = $false               
                    break
                }
            }

            if($null -ne $parentSetting.$Key -and $found)
            {
                $val = $parentSetting.$Key
            }
        }
        catch
        {
            Write-LogError "Failed to read json setting value $Key" $_.Exception
        }
    }
    else
    {
        try
        {       
            $val = Get-ItemPropertyValue -Path (Get-RegPath $SubPath) -Name $Key -ErrorAction SilentlyContinue
        }
        catch 
        {
            if($_.Exception.HResult -ne -2147024809) # Skip reporting missing values
            {
                Write-LogError "Failed to read registry setting value $Key" $_.Exception
            }
        }
    }

    if(-not $val) 
    {
        $defautValue
    }
    else
    {
        $val
    }
}

function Get-RegPath
{
    param($SubPath)

    $path = "HKCU:\Software\CloudAPIPowerShellManagement"
    if($SubPath)
    {
        $path = $path + "\" + $SubPath
    }

    $path
}

function Export-Settings
{
    param($fileName)

    try
    {
        $fi = [IO.FileInfo]$fileName
        if($fi.Directory.Exists -eq $false)
        {
            $fi.Directory.Create()
        }
    }
    catch
    {
        Write-LogError "Failed to create folder for settings file" $_.Exception
        return
    }

    $settingObj = [ordered]@{}
    Add-RegKeyToSettings $settingObj "HKCU:\Software\CloudAPIPowerShellManagement"
    $json = $settingObj | ConvertTo-Json -Depth 20
    try
    {
        $json | Out-File -filePath $fileName -encoding utf8 -Force -ErrorAction Stop
    }
    catch
    {
        Write-LogError "Failed to save json setting file" $_.Exception
    }
}

function Add-RegKeyToSettings
{
    param($settingObj, $regKey)

    try
    {
        $keyObj = Get-Item -Path $regKey
        foreach($keyValue in ($keyObj.GetValueNames() | Sort))
        {
            try
            {
                $settingObj.Add($keyValue, $keyObj.GetValue($keyValue))
            }
            catch
            {
                Write-LogError "Failed to add setting from reg key $keyValue in $regKey" $_.Exception
            }
        }

        foreach($subKey in ($keyObj.GetSubKeyNames() | Sort))
        {

            $settingObjSub = [ordered]@{}
            $settingObj.Add($subKey, $settingObjSub)
            try
            {
                Add-RegKeyToSettings $settingObjSub ($regKey + '\' + $subKey)
            }
            catch
            {
                Write-LogError "Failed to add setting for reg subkey $subKey in $regKey" $_.Exception
            }                
        }        
    }
    catch
    {
        Write-LogError "Failed to add reg keys to json settings" $_.Exception
    }
}

function Remove-TenantSetting
{
    param($settingValue)
    
    $subPath = ($global:Organization.Id + "\" + $settingValue.SubPath)

    if($global:JsonSettingsObj)
    {
        if($SubPath)
        {
            $arrParts = $SubPath.TrimEnd(@('/','\')).Split(@('/','\'))
        }
        else
        {
            $arrParts = @()
        }

        $parentSetting = $global:JsonSettingsObj

        foreach($part in $arrParts)
        {
            if(($parentSetting.PSObject.Properties | Where Name -eq $part))
            {
                $parentSetting = $parentSetting.$part
            }
            else
            {     
                return
            }
        }
        
        if(($parentSetting.PSObject.Properties | Where Name -eq $settingValue.Key))
        {
            $parentSetting.PSObject.Properties.Remove($settingValue.Key) 
        }

    }
    else
    {
        $regPath = Get-RegPath $subPath
        try
        {
            $temp = Get-Item -LiteralPath $regPath -ErrorAction SilentlyContinue
            if(($temp.Property -contains $settingValue.Key))
            {
                Remove-ItemProperty -Path $regPath -Name $settingValue.Key -Force -ErrorAction Stop
            }
        }
        catch
        {
            Write-LogError "Failed to remove reg value: $($settingValue.Key) in key $($regPath)" $_.Exception
        }        
    }
}

function Get-IsTenantSettingConfigured
{
    param($settingValue)
    
    $subPath = ($global:Organization.Id + "\" + $settingValue.SubPath)

    if($global:JsonSettingsObj)
    {
        if($SubPath)
        {
            $arrParts = $SubPath.TrimEnd(@('/','\')).Split(@('/','\'))
        }
        else
        {
            $arrParts = @()
        }

        $parentSetting = $global:JsonSettingsObj

        foreach($part in $arrParts)
        {
            if(($parentSetting.PSObject.Properties | Where Name -eq $part))
            {
                $parentSetting = $parentSetting.$part
            }
            else
            {     
                return $false
            }
        }

        return ($null -ne ($parentSetting.PSObject.Properties | Where Name -eq $settingValue.Key))

    }
    else
    {
        $regPath = Get-RegPath $subPath
        try
        {
            $temp = Get-Item -LiteralPath $regPath -ErrorAction Stop
            return ($temp.GetValueNames() -contains $settingValue.Key)
        }
        catch
        {

        }        
    }
    return $false
}
#endregion

#region Setting functions

########################################################################
#
# Settings functions
#
########################################################################

function Add-SettingsItem
{
    param($settingItem, $settingValue)
    
    $rd = [System.Windows.Controls.RowDefinition]::new()
    $rd.Height = [double]::NaN            
    $spSettings.RowDefinitions.Add($rd)
    $settingItem.SetValue([System.Windows.Controls.Grid]::RowProperty,$spSettings.RowDefinitions.Count-1)
    
    if(-not $settingValue) 
    {
        $settingItem.SetValue([System.Windows.Controls.Grid]::ColumnSpanProperty, 99)
    }
    else 
    {
        if($settingValue.Description)
        {
            $descriptionInfo = "<Rectangle Style=`"{DynamicResource InfoIcon}`" ToolTip=`"$($settingValue.Description)`" Margin=`"5,0,0,0`" />"
        }
    
        $xaml = @"
            <StackPanel $wpfNS Orientation="Horizontal" Margin="5,5,5,0">
                <TextBlock Text="$($settingValue.Title)" VerticalAlignment="Center"/>
                $descriptionInfo
            </StackPanel>
"@        

        if($script:tenantSettings -and $settingValue)
        {
            #_IsChecked
            $tenantConfig = [System.Windows.Controls.CheckBox]::new()
            $tenantConfig.ToolTip = "Enable tenant specific setting"
            $tenantConfig.SetValue([System.Windows.Controls.Grid]::RowProperty,$spSettings.RowDefinitions.Count-1)
            $tenantConfig.SetValue([System.Windows.Controls.Grid]::ColumnProperty, 0)
            $tenantConfig.Margin = "0,5,0,0"
            $tenantConfig.Tag = $settingValue
            $tenantConfig.IsChecked = (Get-IsTenantSettingConfigured $settingValue)
            $settingItem.IsEnabled = $tenantConfig.IsChecked
            $tenantConfig.add_Click({
                    if($this.Tag.Control) { $this.Tag.Control.IsEnabled = $this.IsChecked }
                }
            )
            $spSettings.AddChild($tenantConfig)
        }

        $settingsTitle = [Windows.Markup.XamlReader]::Parse($xaml)
        $settingsTitle.SetValue([System.Windows.Controls.Grid]::RowProperty,$spSettings.RowDefinitions.Count-1)
        $settingsTitle.SetValue([System.Windows.Controls.Grid]::ColumnProperty, 1)

        $settingItem.SetValue([System.Windows.Controls.Grid]::ColumnProperty, 2)
        $spSettings.AddChild($settingsTitle)
        $settingItem.Margin = "0,5,0,0"
    }     
    $spSettings.AddChild($settingItem)
}

function Add-SettingTextBox
{
    param($id, $value)

    $xaml =  @"
<TextBox $wpfNS Name="$($id)" Tag="$title">$value</TextBox>
"@
    return [Windows.Markup.XamlReader]::Parse($xaml)
}

function Add-SettingCheckBox
{
    param($id, $value)

    $tmpValue = ($value -eq $true -or $value -eq "true").ToString().ToLower()

    $xaml =  @"
<CheckBox $wpfNS Name="$($id)" IsChecked="$($tmpValue)" />
"@
    return [Windows.Markup.XamlReader]::Parse($xaml)
}

function Add-SettingComboBox
{
    param($id, $value, $settingObj)

    $nameProp = ?? $settingObj.DisplayMemberPath "Name"
    $valueProp = ?? $settingObj.SelectedValuePath "Value"

    $xaml =  @"
<ComboBox $wpfNS Name="$($id)" DisplayMemberPath="$($nameProp)" SelectedValuePath="$($valueProp)" />
"@
    $xamlObj = [Windows.Markup.XamlReader]::Parse($xaml)

    $xamlObj.ItemsSource = $settingObj.ItemsSource
    if($value)
    {
        $xamlObj.SelectedValue = $value
    }

    $xamlObj
}

function Add-SettingFolder
{
    param($id, $value)
    $xaml = @"
<Grid $wpfNS HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,5,0,0">
    <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*" />  
        <ColumnDefinition Width="5" />                              
        <ColumnDefinition Width="Auto" />                                
    </Grid.ColumnDefinitions> 
    <TextBox Name="$($id)">$value</TextBox>
    <Button Grid.Column="2" Name="browse_$($id)" Padding="5,0,5,0" Width="50">...</Button>
</Grid>

"@

    $obj = [Windows.Markup.XamlReader]::Parse($xaml)

    $btnBrowse = $obj.FindName("browse_$($id)")
    $txtObj = $obj.FindName($id)
    if($btnBrowse)
    {
        $btnBrowse.Tag = $txtObj
        $btnBrowse.Add_Click({
            $folder = Get-Folder $this.Tag.Text
            if($folder) { $this.Tag.Text = $folder }
        })
    }
    return $obj
}

function Add-SettingValue
{
    param($settingValue)

    $id = "id_" + [Guid]::NewGuid().ToString('n')

    if($settingValue.TenantSettings -eq $false -and $script:tenantSettings)
    {
        return # Value nut supported in Tenant Settings
    }
    elseif($settingValue.GlobalSettings -eq $false -and $script:tenantSettings -ne $true)
    {
        return # Value nut supported in Global Settings
    }    

    $value = Get-SettingValue $settingValue.Key -GlobalOnly:($script:tenantSettings -ne $true)

    if($settingValue.Type -eq "folder")
    {
        $settingObj = Add-SettingFolder $id $value
    }
    elseif($settingValue.Type -eq "Boolean")
    {
        $settingObj = Add-SettingCheckBox $id $value
    }
    elseif($settingValue.Type -eq "List")
    {
        $settingObj = Add-SettingComboBox $id $value $settingValue
    }
    else
    {
        $settingObj = Add-SettingTextBox $id $value
    }

    if($settingObj) 
    {         
        Add-SettingsItem $settingObj $settingValue
        # Find the control in the setting object that contains the actual value
        # $settingObj might be a grid that contains the TextBox with the settings value
        $ctrl = $settingObj.FindName($id)
        if(($settingValue | Get-Member -MemberType NoteProperty -Name "Control"))
        {
            $settingValue.Control = $ctrl
        }
        else
        {
            $settingValue | Add-Member -MemberType NoteProperty -Name "Control" -Value $ctrl
        }        
    }
}

function Add-SettingTitle
{
    param($title, $marginTop = "0")

    $xaml =  @"    
    <TextBlock $wpfNS Text="$title" Background="{DynamicResource TitleBackgroundColor}" FontWeight="Bold" Padding="5" Margin="0,$marginTop,0,0" />
"@
    
    #$global:spSettings.Children.Add([Windows.Markup.XamlReader]::Parse($xaml))
    Add-SettingsItem ([Windows.Markup.XamlReader]::Parse($xaml)) | Out-Null
}

function Show-SettingsForm
{
    param([switch]$Tenant)

    $settingsStr =  Get-Content ($global:AppRootFolder+ "\Xaml\SettingsForm.xaml")

    $settingsForm = [Windows.Markup.XamlReader]::Parse($settingsStr)
    $global:settingControls = @()
    $global:spSettings = $settingsForm.FindName("spSettings")

    $script:tenantSettings = ($Tenant -eq $true)
    Add-XamlEvent $settingsForm "btnSave" "Add_Click" ({        
        Save-AllSettings
    })

    Add-XamlEvent $settingsForm "btnClose" "Add_Click" ({
        $script:tenantSettings = $null
        Show-ModalObject
    })

    if($JsonSettingsObj -or $script:tenantSettings -eq $true)
    {
        Set-XamlProperty $settingsForm "btnExport" "Visibility" "Collapsed"
    }
    else
    {
        Add-XamlEvent $settingsForm "btnExport" "Add_Click" ({
            $sf = [System.Windows.Forms.SaveFileDialog]::new()
            $sf.FileName = $script:currentObjName
            $sf.DefaultExt = "*.json"
            $sf.Filter = "Json (*.json)|*.json|All files (*.*)|*.*"
            if($sf.ShowDialog() -eq "OK")
            {
                Export-Settings $sf.FileName
            }         
        })
    }
    
    $tmp = $global:appSettingSections | Where-Object Id -eq "General"
    if($tmp.Values.Count -gt 0)
    {
        Add-SettingTitle $tmp.Title
        foreach($settingObj in $tmp.Values)
        {
            Add-SettingValue $settingObj
        }
    }

    foreach($section in $global:appSettingSections)
    {
        if(-not ($settingObj | Get-Member -MemberType NoteProperty -Name "Priority"))
        {
            $settingObj | Add-Member -MemberType NoteProperty -Name "Priority" -Value 100
        } 
        if($settingObj.Priority -lt 1) { $settingObj.Priority = 1}
    }

    foreach($section in ($global:appSettingSections | Where-Object Id -ne "General" | Sort-Object -Property Priority,Title))
    {
        if($section.Values.Count -eq 0) { continue }
        Add-SettingTitle $section.Title 5
        foreach($settingObj in $section.Values)
        {
            Add-SettingValue $settingObj
        }
    }
    Show-ModalObject $settingsForm
}

function Add-DefaultSettings
{
    $global:appSettingSections = @()

    $global:appSettingSections += (New-Object PSObject -Property @{
            Title = "General"
            Id = "General"
            Values = @()
    })

    Add-SettingsObject (New-Object PSObject -Property @{
            Title = "Log file"
            Key = "LogFile"
            Type = "File"
    }) "General"

    Add-SettingsObject (New-Object PSObject -Property @{
            Title = "Max log file size"
            Key = "LogFileSize"
            Type = "Int"
            DefaultValue = 1024
    }) "General"

    Add-SettingsObject (New-Object PSObject -Property @{
            Title = "Debug"
            Key = "Debug"
            Type = "Boolean"
            DefaultValue = $false
    }) "General"

    Add-SettingsObject (New-Object PSObject -Property @{
        Title = "Hide No-access items"
        Key = "HideNoAccess"
        Type = "Boolean"
        Description="Remove items from the menu if object permissions is missing. Default is to mark them with red"
        DefaultValue = $false
    }) "General"

    Add-SettingsObject (New-Object PSObject -Property @{
        Title = "Preview"
        Key = "PreviewFeatures"
        Type = "Boolean"
        DefaultValue = $false
        Description = "Enable featurs that are marked as Preview. This might require a restart and prompt for consent"
    }) "General"
}

function Add-SettingsObject
{
    param($obj, $section)

    $section = $global:appSettingSections | Where-Object Id -eq $section
    if(-not $section) 
    {
        Write-Log "Could not find section $section" 3
        return 
    }
    $section.Values += $obj
}

function Save-AllSettings
{
    Write-Status "Save settings"
    $dt1 = Get-Date
    $curHideNoAccess = Get-SettingValue "HideNoAccess"

    foreach($section in $global:appSettingSections)
    {
        foreach($settingObj in $section.Values)
        {
            if(-not $settingObj.Control) { continue }
            if($settingObj.Control.IsEnabled -eq $false -and $script:tenantSettings)
            {
                Remove-TenantSetting $settingObj
                continue
            }

            $valueFound = $false
            if($settingObj.Control.GetType().Name -eq "TextBox")
            {
                $value = $settingObj.Control.Text
                if($settingObj.Type -eq "Int")
                {
                    try
                    {
                        $value = [int]$value
                    }
                    catch 
                    {
                        # Log or set invalid
                        $value = $settingObj.Value 
                    }                    
                }
                $valueFound = $true
            }
            elseif($settingObj.Control.GetType().Name -eq "CheckBox")
            {
                $value = $settingObj.Control.IsChecked
                $valueFound = $true
            }
            elseif($settingObj.Control.GetType().Name -eq "ComboBox")
            {
                Write-LogDebug "$($settingObj.Control.Text) | $($settingObj.Control.SelectedIndex)"
                if($settingObj.Control.SelectedIndex -eq -1)
                {
                    $value = $settingObj.Control.Text                    
                }
                else
                {
                    $value = $settingObj.Control.SelectedValue
                }
                $valueFound = $true
            }

            if($valueFound)
            {
                if($script:tenantSettings)
                {
                    $subPath = ($global:Organization.Id + "\" + $settingObj.SubPath)
                }
                else
                {
                    $subPath = $settingObj.SubPath
                }
                Save-Setting $subPath $settingObj.Key $value 
            }
        }
    }
    
    if($global:currentViewObject.ViewInfo.SaveSettings)
    {
        & $global:currentViewObject.ViewInfo.SaveSettings
    }

    Initialize-Settings -Updated

    $newHideNoAccess = Get-SettingValue "HideNoAccess"
    if($curHideNoAccess -ne $newHideNoAccess )
    {
        Show-ViewMenu
    }
    
    if($dt1.AddSeconds(1) -lt (Get-Date))
    {
        Start-Sleep -Seconds 1 # It goes to quick...ToDo: Do this in a better way
    }
    Write-Status ""
}

function Get-SettingValue
{
    param($Key, $defaultValue, [switch]$GlobalOnly, [switch]$TenantOnly, $TenantID)

    foreach($section in $global:appSettingSections)
    {
        $settingObj = $section.Values | Where Key -eq $Key
        if($settingObj) { break }
    }

    if(-not $defaultValue) { $defaultValue = $settingObj.DefaultValue }

    $value = $null    
    if(-not $TenantID) { $TenantID = $global:Organization.Id}

    if($GlobalOnly -ne $true -and $TenantID)
    {
        # Try get Tenant specific value first
        $value = Get-Setting ($TenantID + "\" + $settingObj.SubPath) $settingObj.Key
    }

    if($null -eq $value -and $TenantOnly -ne $true)
    {
        # Get global setting value if tenant value was not found
        $value = Get-Setting $settingObj.SubPath $settingObj.Key $defaultValue
    }

    if($value)
    {
        if($settingObj.Type -eq "Boolean")
        {
            $value = $value -eq $true -or $value -eq "true" 
        }
        elseif($settingObj.Type -eq "Boolean")
        {
            try
            {
                $value = [int]$value
            }
            catch
            {
                if($settingObj.DefaultValue)
                {
                    try
                    {
                        $value = [int]$settingObj.DefaultValue
                    }
                    catch { }
                }
            }
        }

        # Keep last read value
        if($settingObj -and ($settingObj | Get-Member -MemberType NoteProperty -Name "Value"))
        {
            $settingObj.Value = $value # Keep last read value
        }
        else
        {
            $settingObj | Add-Member -MemberType NoteProperty -Name "Value" -Value $value 
        }
    }
    $value
}

#endregion

#region Menu functions

#####################################################################################################
#
# Menu functions
#
#####################################################################################################

function Add-ViewObject
{
    param($viewObject)

    $global:viewObjects += New-Object PSObject -Property @{ ViewInfo = $viewObject; ViewItems = @() }
}

function Add-ViewItem
{
    param($viewItem)

    $viewObject = $global:viewObjects | Where { $_.ViewInfo.Id -eq $viewItem.ViewID }
    if(-not $viewObject) 
    {
        if(($arrMenuInlcude -and $arrMenuInlcude -notcontains $viewItem.ViewID) -or ($arrMenuExlcude -and $arrMenuExlcude -contains $viewItem.ViewID)) { return }

        Write-Log "Could not find menu with id $($viewItem.ViewID). Item $($viewItem.Title) not added" 2
        return
    }

    ### !!! ToDo: Should not be here...
    if(-not ($viewItem.PSObject.Properties | Where Name -eq "ImportOrder"))
    {
        $viewItem | Add-Member -NotePropertyName "ImportOrder" -NotePropertyValue 1000
    }

    foreach($scope in $viewItem.Permissons)
    {
        if($viewObject.ViewInfo.Permissions -is [Object[]] -and  $viewObject.ViewInfo.Permissions -notcontains $scope) { $viewObject.ViewInfo.Permissions += $scope }
    }

    if($viewItem.Icon -or [IO.File]::Exists(($global:AppRootFolder + "\Xaml\Icons\$($viewItem.Id).xaml")))
    {
        $ctrl = Get-XamlObject ($global:AppRootFolder + "\Xaml\Icons\$((?? $viewItem.Icon $viewItem.Id)).xaml")    
        $viewItem | Add-Member -NotePropertyName "IconImage" -NotePropertyValue $ctrl
    }

    $viewObject.ViewItems += $viewItem
}

function Show-View
{
    param($viewId)

    if(($global:viewObjects | measure).Count -eq 0)
    {
        Write-Log "No View Objects loaded!" 3
        return
    }

    if(-not $viewId)
    {
        # Use first View if not specified
        # ToDo: Use last or default view
        $viewId = $global:viewObjects[0].ViewInfo.Id
    }
    
    if($global:currentViewObject.ViewInfo.ID -eq $viewId) { return } # Current view already selected

    # Get the View object
    $viewObject = $global:viewObjects | Where { $_.ViewInfo.Id -eq $viewId }
    if(-not $viewObject) 
    {
        Write-Log "Could not find View with id $($viewId)" 3
        return
    }
    Write-Log "Change view to $($viewObject.ViewInfo.Title)"

    if($global:currentViewObject -ne $viewObject -and $global:currentViewObject.ViewInfo.Deactivating)
    {
        Write-Log "Deactivating View $($global:currentViewObject.ViewInfo.Title)"
        & $global:currentViewObject.ViewInfo.Deactivating
    }    

    $global:currentViewObject = $viewObject

    Show-ViewMenu

    $lblMenuTitle.Content = $viewObject.ViewInfo.Title

    $grdViewPanel.Children.Clear()

    if($viewObject.ViewInfo.Authenticate)
    {
        $global:txtSplashText.Text = "Authenticate"
        [System.Windows.Forms.Application]::DoEvents()
        & $viewObject.ViewInfo.Authenticate
    }

    if($viewObject.ViewInfo.Activating)
    {
        Write-Log "Activating View $($viewObject.ViewInfo.Title)"
        & $viewObject.ViewInfo.Activating
    }

    if($viewObject.ViewInfo.ViewPanel)
    {
        $grdViewPanel.Children.Add($viewObject.ViewInfo.ViewPanel) | Out-Null
    }

    Set-MainTitle

    Show-AuthenticationInfo

    if($viewObject.ViewInfo.HideMenu -eq $true)
    {
        $global:grdViewItemMenu.Visibility = "Collapsed"
    }
    else
    {
        $global:grdViewItemMenu.Visibility = "Visible"
    }

    if($viewObject.ViewInfo.Activated)
    {
        Write-Log "Activated View $($viewObject.ViewInfo.Title)"
        & $viewObject.ViewInfo.Activated
    }

    Invoke-ModuleFunction "Invoke-ViewActivated"
}

function Show-ViewMenu
{
    $viewObject = $global:currentViewObject

    $viewItems = ?: ($viewObject.ViewInfo.Sort -ne $false) ($viewObject.ViewItems | Sort-Object -Property Title) ($viewObject.ViewItems)

    if((Get-SettingValue "HideNoAccess"))
    {
        $viewItems = $viewItems | Where { $_."@HasPermissions" -ne $false }
    }

    $lstMenuItems.ItemsSource = @($viewItems)
}

#endregion

#region Main Window
function Set-MainTitle
{    
    if(-not $global:window -or -not $global:currentViewObject.ViewInfo.Title) { return }

    Write-LogDebug "Set main title to $($global:currentViewObject.ViewInfo.Title)"

    $global:window.Title = ?? $global:currentViewObject.ViewInfo.Title "Cloud API PowerShell Management"
}

function Get-MainWindow
{
    try 
    {
        [xml]$xaml = Get-Content ($global:AppRootFolder + "\Xaml\MainWindow.xaml")
        [xml]$styles = Get-Content ($global:AppRootFolder + "\Themes\Styles.xaml")

        ### Update relative path to full path for ResourceDictionary
        [System.Xml.XmlNamespaceManager] $nsm = $xaml.NameTable;
        $nsm.AddNamespace("s", 'http://schemas.microsoft.com/winfx/2006/xaml/presentation');
        foreach($rsdNode in ($xaml.SelectNodes("//s:ResourceDictionary[@Source]", $nsm)))
        {
            $rsdNode.Source = (Join-Path ($PSScriptRoot) ($rsdNode.Source)).ToString()
        }
        
        # Add Styles 
        foreach($node in $styles.DocumentElement.ChildNodes)
        {
            $tmpNode = $xaml.CreateElement("Temp")
            $tmpNode.InnerXml = $node.OuterXml
            $xaml.Window.'Window.Resources'.ResourceDictionary.AppendChild($tmpNode.Style) | Out-Null
        }
        $global:window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    }
    catch
    {
        Write-LogError "Failed to initialize main window" $_.Exception
        return
    }

    # ToDo: Convert to a list for data binding
    Add-XamlEvent $window "mnuSettings" "Add_Click" -scriptBlock ([scriptblock]{ Show-SettingsForm })
    Add-XamlEvent $window "mnuTenantSettings" "Add_Click" -scriptBlock ([scriptblock]{ Show-SettingsForm -Tenant })
    Add-XamlEvent $window "mnuUpdates" "Add_Click" -scriptBlock ([scriptblock]{ Show-UpdatesDialog })
    Add-XamlEvent $window "mnuAbout" "Add_Click" -scriptBlock ([scriptblock]{ Show-AboutDialog })
    Add-XamlEvent $window "mnuExit" "Add_Click" -scriptBlock ([scriptblock]{ 
        if([System.Windows.MessageBox]::Show("Are you sure you want to exit?", "Exit?", "YesNo", "Question") -eq "Yes")
            {
                $window.Close() 
            }
        }
    )

    Add-XamlVariables $xaml $window

    $lstMenuItems.Add_SelectionChanged({
        if($global:currentViewObject.ViewInfo.ItemChanged)
        {
            & $global:currentViewObject.ViewInfo.ItemChanged
        }
    })

    $global:grdPopup.add_MouseLeftButtonDown( { Hide-Popup } )
  
    # ToDo: !!! Intune should not be default icon...
    $iconFile = "$($global:AppRootFolder)\Intune.ico"
    if([io.File]::Exists($iconFile))
    {
        $Window.Icon = $iconFile
    }

    $window.Add_Closed({
    }) 

    $window.add_Loaded({
        $global:SplashScreen.Hide()
        $global:window.Activate()
        [System.Windows.Forms.Application]::DoEvents()
        #$global:window.Topmost = $true
        #$global:window.Topmost = $false
        #$global:window.Focus()

        $global:MainAppStarted = $true

        if($global:FirstTimeRunning)
        {
            $script:welcomeForm = Get-XamlObject ($global:AppRootFolder + "\Xaml\Welcome.xaml") -AddVariables
            
            Add-XamlEvent $script:welcomeForm "gitHubLink" "Add_RequestNavigate" ({ [System.Diagnostics.Process]::Start($_.Uri.AbsoluteUri); $_.Handled = $true })
            Add-XamlEvent $script:welcomeForm "licenseLink" "Add_RequestNavigate" ({ [System.Diagnostics.Process]::Start($_.Uri.AbsoluteUri); $_.Handled = $true })
            
            Add-XamlEvent $script:welcomeForm "chkAcceptConditions" "add_click" {
                $global:btnAcceptConditions.IsEnabled = ($this.IsChecked -eq $true)
            }            

            Add-XamlEvent $script:welcomeForm "btnAcceptConditions" "add_click" {
                Save-Setting "" "LicenseAccepted" "True"
                Save-Setting "" "FirstTimeRunning" "False"
                Show-ModalObject
                
                if($global:currentViewObject.ViewInfo.Authentication.ShowErrors)
                {
                    & $global:currentViewObject.ViewInfo.Authentication.ShowErrors
                }                
            }

            Add-XamlEvent $script:welcomeForm "btnCancel" "add_click" {
                if([System.Windows.MessageBox]::Show("Conditions not accepted`n`nDo you want to close the application?", "Close App?", "YesNo", "Warning") -eq "Yes")
                {
                    $window.Close()                    
                }
            }

            Show-ModalForm $window.Title $script:welcomeForm -HideButtons
        }
    })

    foreach($view in $global:viewObjects)
    {
        $subItem = [System.Windows.Controls.MenuItem]::new()
        $subItem.Header = $view.ViewInfo.Title
        $subItem.Tag = $view.ViewInfo.Id
        $subItem.Add_Click({
            if($this.Tag)
            {
                Show-View $this.Tag
            }
        })
        $global:mnuViews.AddChild($subItem) | Out-Null
    }    
}

#endregion

#region Module functions
function Invoke-ModuleFunction
{
    param($function)

    Write-Log "Trigger function $function"

    foreach($module in $global:loadedModules)
    {
        # Get command with ExportedFunctions instead of Get-Command
        $cmd = $module.ExportedFunctions[$function]
        if($cmd) 
        {
            Write-Log "Trigger $function in $($module.Name)"
            Invoke-Command -ScriptBlock $cmd.ScriptBlock
        }
        else
        {
            #Write-Log "$function not found in $($module.Name)" 2
        }
    }
}

#endregion

#region JWTToken

### See JWT token documentation for more info: https://tools.ietf.org/html/rfc7519
### AccessToken documentation https://docs.microsoft.com/en-us/azure/active-directory/develop/access-tokens
function Get-JWTtoken 
{ 
    param($token)

    if(-not $token -or -not $token.StartsWith("eyJ"))  { Write-Log "Invalid token" 3; return }

    # First part is the header. Second part is the payload. Third part is the signature
    $arr = $token.Split(".")

    if($arr.Count -lt 2) { Write-Log "Invalid token" 3; return }
    
    $header = $arr[0].Replace('-', '+').Replace('_', '/') # change base64url to base64
    while ($header.Length % 4) { $header += "=" } # Add padding to match required length 
    
    $payload = $arr[1].Replace('-', '+').Replace('_', '/') # change base64url to base64
    while ($payload.Length % 4) { $payload += "=" } # Add padding to match required length

    return (New-Object PSObject -Property @{
        Header=(([System.Text.Encoding]::UTF8.GetString(([System.Convert]::FromBase64String($header)))) | ConvertFrom-Json)
        Payload=(([System.Text.Encoding]::UTF8.GetString(([System.Convert]::FromBase64String($payload)))) | ConvertFrom-Json)
    })
}
#endregion

function Add-GridObject
{
    param($grid, $obj)

    $rd = [System.Windows.Controls.RowDefinition]::new()
    $rd.Height = [double]::NaN
    $obj.SetValue([System.Windows.Controls.Grid]::RowProperty,$grid.RowDefinitions.Count) | Out-Null
    $grid.RowDefinitions.Add($rd) | Out-Null
    $grid.Children.Add($obj) | Out-Null
}

function Get-IsAdmin
{
    (New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Get-NumericUpDownControl
{
    param($id, [decimal]$minValue = 0, [decimal]$maxValue = 9999, [int]$step = 1)

    try 
    {
        [xml]$xaml = Get-Content ($global:AppRootFolder + "\Xaml\NumericUpDown.xaml")                 
        $xamlObj = ([Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml)))

        $xamlObj.Name = $id
        $xamlObj.Children[0].Name = $id + "_TextBox"
        $xamlObj.Children[1].Name = $id + "_UpButton"
        $xamlObj.Children[1].Name = $id + "_DownButton"

        $settings = [PSCustomObject]@{
            MinValue = $minValue
            MaxValue = $maxValue
            Step = $step
            _lastKnownValue = $null
        }

        $xamlObj | Add-Member -MemberType NoteProperty -Name "Settings" -Value $settings
        
        $xamlObj.Children[0].Add_TextChanged({
            $val = $null
            if([decimal]::TryParse($this.Parent.Children[0].Text, [ref]$val))
            {
                $this.Parent.Settings._lastKnownValue = $val;
            } 
        })

        $xamlObj.Children[0].Add_LostFocus({
            $val = $null
            if([decimal]::TryParse($this.Parent.Children[0].Text, [ref]$val))
            {
                ;
            }
            elseif($this.Parent.Settings._lastKnownValue)
            {
                $val = $this.Parent.Settings._lastKnownValue
            }

            if($val -ne $null)
            {
                if($val -gt $this.Parent.Settings.MaxValue)
                {
                    $val = $this.Parent.Settings.MaxValue
                }
                elseif($val -lt $this.Parent.Settings.MinValue)
                {
                    $val = $this.Parent.Settings.MinValue
                }
                $this.Parent.Children[0].Text = $val.ToString()
            }
        })

        $xamlObj.Children[1].Add_Click({
            $val = $null
            if([decimal]::TryParse($this.Parent.Children[0].Text, [ref]$val))
            {
                $val = $val + $this.Parent.Settings.Step
                if($val -gt $this.Parent.Settings.MaxValue)
                {
                    $val = $this.Parent.Settings.MaxValue
                }
                $this.Parent.Children[0].Text = $val.ToString()
            }
        })

        $xamlObj.Children[2].Add_Click({
            $val = $null
            if([decimal]::TryParse($this.Parent.Children[0].Text, [ref]$val))
            {
                $val = $val - $this.Parent.Settings.Step
                if($val -lt $this.Parent.Settings.MinValue)
                {
                    $val = $this.Parent.Settings.MinValue
                }
                $this.Parent.Children[0].Text = $val.ToString()
            }
        })        
        
        return $xamlObj
            
    }
    catch 
    {
        Write-LogError "Failed to create NumericUpDown control" $_.Exception
        return $null    
    }    

}

function Format-XML
{
    param([xml]$xml, $indent = 2)
    
    if(-not $xml) { return }

    #From: https://devblogs.microsoft.com/powershell/format-xml/
    $StringWriter = New-Object System.IO.StringWriter
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter
    $xmlWriter.Formatting = "indented"
    $xmlWriter.Indentation = $Indent
    $xml.WriteContentTo($XmlWriter)
    $XmlWriter.Flush()
    $StringWriter.Flush()
    $StringWriter.ToString()
}

function Show-LogView
{
    if($script:LogViewObject -and -not $script:LogViewObject.ViewPanel)
    {
        $viewPanel = Get-XamlObject ($global:AppRootFolder + "\Xaml\LogInfo.xaml")
    
        if(-not $viewPanel) { return }

        $script:LogViewObject.ViewPanel = $viewPanel 

        Set-XamlProperty $viewPanel "dgLogInfo" "ItemsSource" $script:LogItems

        Add-XamlEvent $viewPanel "dgLogInfo" "add_selectionChanged" ({ 
            $obj = $this.Parent.FindName("txtLogInfo")
            if($obj)
            {
                $obj.Parent.DataContext = $this.SelectedValue
            }
        })
    }
}

New-Alias -Name ?? -value Invoke-Coalesce
New-Alias -Name ?: -value Invoke-IfTrue
Export-ModuleMember -alias * -function *