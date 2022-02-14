<#

A module that handles custom documentation tasks

This will add properties at runtime that is required for the documentation

This module will also document some objects based on PowerShell functions

#>

function Get-ModuleVersion
{
    '1.0.6'
}

function Invoke-InitializeModule
{
    Add-DocumentationProvicer ([PSCustomObject]@{
        Name="Custom"
        Priority = 1000 # The priority of the Provider. Lower number has higher priority.
        DocumentObject = { Invoke-CDDocumentObject @args }
        GetCustomProfileValue = { Add-CDDocumentCustomProfileValue @args }
        GetCustomChildObject = { Get-CDDocumentCustomChildObjet  @args }
        GetCustomPropertyObject = { Get-CDDocumentCustomPropertyObject  @args }
        AddCustomProfileProperty = { Add-CDDocumentCustomProfileProperty @args }
    })
}

function Invoke-CDDocumentObject
{
    param($documentationObj)

    $obj = $documentationObj.Object
    $objectType = $documentationObj.ObjectType
    $type = $obj.'@OData.Type'

    if($type -eq '#microsoft.graph.conditionalAccessPolicy')
    {
        Invoke-CDDocumentConditionalAccess $documentationObj
        return [PSCustomObject]@{
            Properties = @("Name","Value","Category","SubCategory") #,"RawValue","Description"
        }
    }
    elseif($type -eq '#microsoft.graph.countryNamedLocation')
    {
        Invoke-CDDocumentCountryNamedLocation $documentationObj
        return [PSCustomObject]@{
            Properties = @("Name","Value") 
        }
    }
    elseif($type -eq '#microsoft.graph.ipNamedLocation')
    {
        Invoke-CDDocumentIPNamedLocation $documentationObj
        return [PSCustomObject]@{
            Properties = @("Name","Value") 
        }
    }
    elseif($type -eq '#microsoft.graph.iosMobileAppConfiguration')
    {
        Invoke-CDDocumentiosMobileAppConfiguration $documentationObj
        return [PSCustomObject]@{
            Properties = @("Name","Value","Category","SubCategory")
        }
    }
    elseif($type -eq '#microsoft.graph.targetedManagedAppConfiguration')
    {
        Invoke-CDDocumentManagedAppConfig $documentationObj
        return [PSCustomObject]@{
            Properties = @("Name","Value","Category","SubCategory")
        }
    }
    elseif($type -eq '#microsoft.graph.policySet')
    {
        Invoke-CDDocumentPolicySet $documentationObj
        return [PSCustomObject]@{
            Properties = @("Name","Value","Category","SubCategory")
        }
    }
    elseif($type -eq '#microsoft.graph.windows10CustomConfiguration' -or 
        $type -eq '#microsoft.graph.androidForWorkCustomConfiguration' -or
        $type -eq '#microsoft.graph.androidWorkProfileCustomConfiguration' -or
        $type -eq '#microsoft.graph.androidCustomConfiguration')
    {
        Invoke-CDDocumentCustomOMAUri $documentationObj
        return [PSCustomObject]@{
            Properties = @("Name","Value","Category","SubCategory")
        }
    }
    elseif($type -eq '#microsoft.graph.notificationMessageTemplate')
    {
        Invoke-CDDocumentNotification $documentationObj
        return [PSCustomObject]@{
            Properties = @("Name","Value","Category","SubCategory")
        }
    }    
}

function Get-CDAllManagedApps
{
    if(-not $script:allManagedApps)
    {
        $script:allManagedApps = (Invoke-GraphRequest -Url "/deviceAppManagement/managedAppStatuses('managedAppList')").content.appList
    }
    $script:allManagedApps
}

function Get-CDAllCloudApps
{
    if(-not $script:allCloudApps)
    {
        $script:allCloudApps =(Invoke-GraphRequest -url "/servicePrincipals?`$select=displayName,appId&top=999" -ODataMetadata "minimal").value
    }
    $script:allCloudApps
}

function Get-CDAllTenantApps
{
    if(-not $script:allTenantApps)
    {
        $script:allTenantApps =(Invoke-GraphRequest -url "/deviceAppManagement/mobileApps?`$select=displayName,id&top=999" -ODataMetadata "minimal").value
    }
    $script:allTenantApps
}

function Get-CDMobileApps
{
    param($apps)

    $managedApps = Get-CDAllManagedApps
    $publishedApps = @()
    $customApps = @()
    foreach($tmpApp in $apps)
    {
        $appObj = $managedApps | Where { (($tmpApp.mobileAppIdentifier.packageId -and $_.appIdentifier.packageId -eq $tmpApp.mobileAppIdentifier.packageId) -or ($tmpApp.mobileAppIdentifier.bundleId -and $_.appIdentifier.bundleId -eq $tmpApp.mobileAppIdentifier.bundleId)) -and $_.appIdentifier."@odata.type" -eq $tmpApp.mobileAppIdentifier."@odata.type" }
        if($appObj -and $appObj.isFirstParty)
        {
            $publishedApps += $appObj.displayName
        }
        elseif($appObj)
        {
            $customApps += $appObj.displayName
        }
    }

    @($customApps,$publishedApps)
}

<#
.SYNOPSIS
Custom documentation for a value 

.DESCRIPTION
Ignore or create a custom value for a property
Return false to skip further processing of the property

.PARAMETER obj
The object to check. This could be a property of the profile object

.PARAMETER prop
Current property

.PARAMETER topObj
The profile object 

.PARAMETER propSeparator
Property separator character

.PARAMETER objSeparator
Object separator character
#>

function Add-CDDocumentCustomProfileValue
{
    param($obj, $prop, $topObj, $propSeparator, $objSeparator)
    
    if($obj.'@OData.Type' -eq "#microsoft.graph.windowsDeliveryOptimizationConfiguration" -and
        $prop.entityKey -eq "groupIdSourceSelector")
    {
        Invoke-TranslateOption $obj $prop -SkipOptionChildren | Out-Null
        return $false
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.androidManagedAppProtection" -or 
        $obj.'@OData.Type' -eq "#microsoft.graph.iosManagedAppProtection")
    {
        if($prop.entityKey -eq "apps")
        {
            $customApps,$publishedApps = Get-CDMobileApps $obj.Apps

            Add-PropertyInfo $prop ($publishedApps -join $objSeparator) -originalValue ($publishedApps -join $propSeparator)
            $propInfo = Get-PropertyInfo $prop ($customApps -join $objSeparator) -originalValue ($customApps -join $propSeparator)
            $propInfo.Name = Get-LanguageString "SettingDetails.customApps"
            $propInfo.Description = ""
            Add-PropertyInfoObject $propInfo
            return $false
        }        
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.windowsInformationProtectionPolicy" -or 
        $obj.'@OData.Type' -eq "#microsoft.graph.mdmWindowsInformationProtectionPolicy")
    {
        if($prop.entityKey -eq "enterpriseIPRanges")
        {
            $IPRanges = @()

            foreach($ipRange in $obj.enterpriseIPRanges)
            {
                $ranges = @()
                
                foreach($range in $ipRange.ranges)
                {
                    $ranges += ($range.lowerAddress + '-' + $range.upperAddress)
                }

                if($ranges.Count -gt 0)
                {
                    $IPRanges += ($ipRange.displayName + $propSeparator + ($ranges -join $propSeparator))
                }
            }

            $tmpArr = ($IPRanges | Where {$_.Contains('.')})
            if(($tmpArr | measure).Count -gt 0)
            {
                foreach($ipV4 in $tmpArr)
                {
                    Add-PropertyInfo $prop $ipV4 -originalValue $ipV4
                }
            }
            else
            {
                Add-PropertyInfo $prop $null
            }

            $tmpArr = ($IPRanges | Where {$_.Contains(':')})            
            
            if(($tmpArr | measure).Count -gt 0)
            {
                foreach($ipV6 in $tmpArr)
                {
                    $propInfo = Get-PropertyInfo $prop $ipV6 -originalValue $ipV6
                    $propInfo.Name = Get-LanguageString "WipPolicySettings.iPv6Ranges"
                    Add-PropertyInfoObject $propInfo
                }
            }
            else
            {
                $propInfo = Get-PropertyInfo $prop $null
                $propInfo.Name = Get-LanguageString "WipPolicySettings.iPv6Ranges"
                Add-PropertyInfoObject $propInfo
            }
            
            return $false
        }
        elseif($prop.entityKey -eq "enterpriseProxiedDomains")
        {
            foreach($tmpObj in $obj.enterpriseProxiedDomains)
            {
                $propValue = ($tmpObj.displayName + $propSeparator + ($tmpObj.proxiedDomains.ipAddressOrFQDN -join $propSeparator))
                Add-PropertyInfo $prop $propValue -originalValue $propValue
            }
            return $false
        }
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.windows*SCEPCertificateProfile")
    {
        if($prop.entityKey -eq "subjectNameFormat" -or $prop.entityKey -eq "subjectAlternativeNameType")
        {
            return $false # Skip these properties
        }        
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.windows10GeneralConfiguration")
    {        
        if($prop.EntityKey -eq "startMenuAppListVisibility")
        {
            $value = $obj.startMenuAppListVisibility
            if($value.IndexOf(", ") -eq -1)
            {
                $value = $value -replace ",",", " # Option values in json file has space afte , but value in object don't
            }
            Invoke-TranslateOption $obj $prop -PropValue $value
            return $false
        }

        $privacyAccessControls = $obj.privacyAccessControls | Where { $_.dataCategory -eq $prop.EntityKey -and $_.appDisplayName -eq $null }
        if($privacyAccessControls)
        {
            Invoke-TranslateOption $privacyAccessControls $prop -PropValue ($privacyAccessControls.accessLevel)
            return $false
        }
    }
    elseif($topObj.'@OData.Type' -like "#microsoft.graph.windows10EndpointProtectionConfiguration")
    {
        if($prop.EntityKey -eq "applicationGuardEnabled") { return $false }
        elseif($prop.EntityKey -eq "bitLockerRecoveryPasswordRotation") 
        { 
            Invoke-TranslateOption  $topObj $prop 
            return $false
        }
    }
    elseif($topObj.'@OData.Type' -like "#microsoft.graph.windowsHealthMonitoringConfiguration")
    {
        if($prop.EntityKey -eq "configDeviceHealthMonitoringScope") 
        { 
            if(($prop.options | Where value -eq "healthMonitoring"))
            {
                # Duplicate sections for health monitoring. Remove the old one
                return $false
            }
        }
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.windows10VpnConfiguration")
    {
        if($prop.EntityKey -eq "enableSplitTunneling" -and $prop.enabled -eq $false) 
        { 
            # SplitTunneling settings are moved to another file
            return $false
        }
        elseif($prop.EntityKey -eq "eapXml" -and $obj.eapXml)
        {
            $propValue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($obj.eapXml)) 
            Add-PropertyInfo $prop $propValue -originalValue $propValue
            return $false
        }
    }    
}

<#
.SYNOPSIS
Change property source object before getting the property 

.DESCRIPTION
By default the object itself is always used when checking property values. 
This function changes the source object BEFORE a property is documented

.PARAMETER obj
The object to check

.PARAMETER prop
Current property

#>
function Get-CDDocumentCustomPropertyObject
{
    param($obj, $prop)

    if($obj.'@OData.Type' -like "#microsoft.graph.windows10EndpointProtectionConfiguration")
    {
        if($prop.EntityKey -eq "startupAuthenticationRequired")
        {
            return $obj.bitLockerSystemDrivePolicy
        }
        elseif($prop.EntityKey -eq "bitLockerSyntheticFixedDrivePolicyrequireEncryptionForWriteAccess")
        {
            return $obj.bitLockerFixedDrivePolicy
        }
        elseif($prop.EntityKey -eq "bitLockerSyntheticRemovableDrivePolicyrequireEncryptionForWriteAccess")
        {
            return $obj.bitLockerRemovableDrivePolicy
        }        
    }

}

<#
.SYNOPSIS
Changes the source object to use for child properties

.DESCRIPTION
By default the object itself is always used when getting property values. 
This function changes the source property AFTER the property is processed but BEFORE child properties are documented

.PARAMETER obj
The object to check

.PARAMETER prop
Current property

#>
function Get-CDDocumentCustomChildObjet
{
    param($obj, $prop)

    if($obj.'@OData.Type' -like "#microsoft.graph.windows10GeneralConfiguration")
    {
        if($prop.EntityKey -eq "syntheticDefenderDetectedMalwareActionsEnabled")
        {
            return $obj.defenderDetectedMalwareActions
        }
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.iosDeviceFeaturesConfiguration")
    {
        if($prop.EntityKey -eq "kerberosPrincipalName")
        {
            return $obj.singleSignOnSettings
        }
        elseif($prop.EntityKey -eq "singleSignOnExtensionType")
        {
            return $obj.iosSingleSignOnExtension
        }
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.macOSDeviceFeaturesConfiguration")
    {
        if($prop.EntityKey -eq "singleSignOnExtensionType")
        {
            return $obj.macOSSingleSignOnExtension
        }
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.windows10EndpointProtectionConfiguration")
    {
        if($prop.EntityKey -eq "applicationGuardPrintSettings")
        {
            return $obj.applicationGuardPrintSettings
        }
        if($prop.EntityKey -eq "firewallSyntheticIPsecExemptions")
        {
            return $obj.firewallSyntheticIPsecExemptions
        }
    }    
}

<#
.SYNOPSIS
Add cutom properties to the object

.DESCRIPTION
Many of the properties in profile translation files are based on calculated values. This function will add these extra properties to the object

.PARAMETER obj
The object to check

.PARAMETER propSeparator
Property separator character

.PARAMETER objSeparator
Object separator character

#>
function Add-CDDocumentCustomProfileProperty
{
    param($obj, $propSeparator, $objSeparator)

    $retValue = $false

    if($obj.'@OData.Type' -eq "#microsoft.graph.androidWorkProfileGeneralDeviceConfiguration" -or
            $obj.'@OData.Type' -eq "#microsoft.graph.androidDeviceOwnerGeneralDeviceConfiguration")
    {
        #Build vpnAlwaysOnPackageIdentifierSelector property
        $packageId = $null
        if(![String]::IsNullOrEmpty($obj.vpnAlwaysOnPackageIdentifier))
        {
            if(-not $obj.vpnAlwaysOnPackageIdentifier -or $obj.vpnAlwaysOnPackageIdentifier -notin @("com.cisco.anyconnect.vpn.android.avf","com.f5.edge.client_ics","com.paloaltonetworks.globalprotect","net.pulsesecure.pulsesecure"))
            {
                $packageId = "custom"
            }
            else
            {
                $packageId = $obj.vpnAlwaysOnPackageIdentifier
            }
        }
        $obj | Add-Member Noteproperty -Name "vpnAlwaysOnPackageIdentifierSelector" -Value $packageId -Force        
        $obj | Add-Member Noteproperty -Name "vpnAlwaysOnEnabled" -Value (![String]::IsNullOrEmpty($obj.vpnAlwaysOnPackageIdentifier)) -Force

        if(($obj.PSObject.Properties | Where Name -eq "globalProxy"))
        {
            $obj | Add-Member Noteproperty -Name "globalProxyEnabled" -Value ($obj.globalProxy -ne $null) -Force
            if($obj.globalProxy.proxyAutoConfigURL)
            {
                $globalProxyTypeSelector = "proxyAutoConfig"
                $obj | Add-Member Noteproperty -Name "globalProxyProxyAutoConfigURL" -Value $obj.globalProxy.proxyAutoConfigURL -Force
            }
            if($obj.globalProxy.host)
            {
                $globalProxyTypeSelector = "direct"
                $obj | Add-Member Noteproperty -Name "globalProxyHost" -Value $obj.globalProxy.host -Force
                $obj | Add-Member Noteproperty -Name "globalProxyPort" -Value $obj.globalProxy.port -Force
                $obj | Add-Member Noteproperty -Name "globalProxyExcludedHosts" -Value $obj.globalProxy.excludedHosts -Force
            }
            $obj | Add-Member Noteproperty -Name "globalProxyTypeSelector" -Value $globalProxyTypeSelector  -Force
        }

        if(($obj.PSObject.Properties | Where Name -eq "factoryResetDeviceAdministratorEmails"))
        {
            $factoryResetProtections = "factoryResetProtectionDisabled"
            if(($obj.factoryResetDeviceAdministratorEmails | measure).Count -gt 0)
            {
                $factoryResetProtections = "factoryResetProtectionEnabled"
            }
            $obj | Add-Member Noteproperty -Name "factoryResetProtections" -Value $factoryResetProtections -Force
            $obj | Add-Member Noteproperty -Name "googleAccountEmailAddressesList" -Value ($obj.factoryResetDeviceAdministratorEmails -join $objSeparator) -Force
        }
        
        if(($obj.PSObject.Properties | Where Name -eq "passwordBlockKeyguardFeatures"))
        {
            $obj | Add-Member Noteproperty -Name "passwordBlockKeyguardFeaturesList" -Value $obj.passwordBlockKeyguardFeatures -Force
        }
        
        if(($obj.PSObject.Properties | Where Name -eq "stayOnModes"))
        {
            $obj | Add-Member Noteproperty -Name "stayOnModesList" -Value $obj.stayOnModes -Force
        }

        if(($obj.PSObject.Properties | Where Name -eq "playStoreMode"))
        {
            $obj | Add-Member Noteproperty -Name "publicPlayStoreEnabled" -Value ($obj.playStoreMode -eq "blockList") -Force
        }
        $retValue = $true
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.androidEasEmailProfileConfiguration")
    {
        if(!($obj.PSObject.Properties | Where Name -eq "domainNameSourceType"))
        {
            $obj | Add-Member Noteproperty -Name "domainNameSourceType" -Value (?: ($obj.customDomainName -ne $null) "CustomDomainName" "AAD") -Force
        }
        $retValue = $true
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.windowsDeliveryOptimizationConfiguration")
    {
        if(!($obj.PSObject.Properties | Where Name -eq "groupIdSourceSelector"))
        {
            $obj | Add-Member Noteproperty -Name "groupIdSourceSelector" -Value (?? $obj.groupIdSource.groupIdSourceOption "notConfigured") -Force
        }
        $retValue = $true
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.windows10GeneralConfiguration")
    {
        if(!($obj.PSObject.Properties | Where Name -eq "networkProxyUseScriptUrlName"))
        {
            $obj | Add-Member Noteproperty -Name "networkProxyUseScriptUrlName" -Value ([String]::IsNullOrEmpty($obj.networkProxyAutomaticConfigurationUrl) -ne $null) -Force
        }

        $obj | Add-Member Noteproperty -Name "syntheticDefenderDetectedMalwareActionsEnabled" -Value ($obj.defenderDetectedMalwareActions -ne $null) -Force
        
        if(!($obj.PSObject.Properties | Where Name -eq "networkProxyUseManualServerName"))
        {
            $obj | Add-Member Noteproperty -Name "networkProxyUseManualServerName" -Value ($obj.networkProxyServer.address -ne $null) -Force
            if($obj.networkProxyServer.address -ne $null)
            {
                $obj | Add-Member Noteproperty -Name "networkProxyServerName" -Value $obj.networkProxyServer.address.Split(':')[0] -Force
                $obj | Add-Member Noteproperty -Name "networkProxyServerPort" -Value $obj.networkProxyServer.address.Split(':')[1] -Force
            }
            else
            {
                $obj | Add-Member Noteproperty -Name "networkProxyServerName" -Value "" -Force
                $obj | Add-Member Noteproperty -Name "networkProxyServerPort" -Value "" -Force
            }
            $exceptions = $null
            if($obj.networkProxyServer.exceptions)
            {
                $exceptions = ($obj.networkProxyServer.exceptions -join $propSeparator)
            }
            $obj | Add-Member Noteproperty -Name "networkProxyExceptionsTextString" -Value $exceptions -Force
            $obj | Add-Member Noteproperty -Name "useForLocalAddresses" -Value ($obj.networkProxyServer.useForLocalAddresses -eq $true) -Force
        }

        $obj | Add-Member Noteproperty -Name "edgeDisplayHomeButton" -Value ($obj.networkProxyServer.useForLocalAddresses -eq $true) -Force

        $searchEngineValue = 0
        if($obj.edgeSearchEngine.edgeSearchEngineOpenSearchXmlUrl -eq "default")
        {
            $searchEngineValue = 1
        }
        elseif($obj.edgeSearchEngine.edgeSearchEngineOpenSearchXmlUrl -eq "bing")
        {
            $searchEngineValue = 2
        }
        elseif($obj.edgeSearchEngine.edgeSearchEngineOpenSearchXmlUrl -eq "https://go.microsoft.com/fwlink/?linkid=842596")
        {
            $searchEngineValue = 3
        }
        elseif($obj.edgeSearchEngine.edgeSearchEngineOpenSearchXmlUrl -eq "https://go.microsoft.com/fwlink/?linkid=842600")
        {
            $searchEngineValue = 4
        }
        elseif($obj.edgeSearchEngine.edgeSearchEngineOpenSearchXmlUrl)
        {
            $searchEngineValue = 5
        }

        $obj | Add-Member Noteproperty -Name "edgeSearchEngineDropDown" -Value $searchEngineValue -Force

        $privacyApps = $obj.privacyAccessControls | Where { $_.appDisplayName -ne $null }

        $curApp = $null

        $perAppPrivacy = @()
        foreach($appItem in $privacyApps)
        {
            if($curApp -ne $appItem.appDisplayName)
            {
                $perAppPrivacy += [PSCustomObject]@{
                    appPackageName = $appItem.appPackageFamilyName
                    appName = $appItem.appDisplayName
                    #exceptions = $obj.privacyAccessControls | Where { $_.appPackageFamilyName -ne $appItem.appPackageFamilyName }
                }
                #($appItem.appPackageFamilyName + $propSeparator + $appItem.appDisplayName)
                $curApp = $appItem.appDisplayName
            }
        }
        $obj | Add-Member Noteproperty -Name "perAppPrivacy" -Value $perAppPrivacy -Force
        
        $retValue = $true
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.androidManagedAppProtection")
    {
        $obj | Add-Member Noteproperty -Name "overrideFingerprint" -Value ($obj.pinRequiredInsteadOfBiometricTimeout -ne $null)
        $obj | Add-Member Noteproperty -Name "pinReset" -Value ($obj.pinRequiredInsteadOfBiometricTimeout -ne $null)
        $obj | Add-Member Noteproperty -Name "managedBrowserSelection" -Value (?: $obj.customBrowserPackageId  "unmanagedBrowser" $obj.managedBrowser)
        
        $retValue = $true
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.iosManagedAppProtection")
    {
        $sendDataOption = $obj.allowedOutboundDataTransferDestinations 
        if($obj.allowedOutboundDataTransferDestinations -eq "managedApps")
        {
            if($obj.disableProtectionOfManagedOutboundOpenInData -eq $false -and 
                $obj.filterOpenInToOnlyManagedApps -eq $true)
                {
                    $sendDataOption = "managedAppsWithOpenInSharing"
                }
            elseif($obj.disableProtectionOfManagedOutboundOpenInData -eq $true -and 
                $obj.filterOpenInToOnlyManagedApps -eq $false)
                {
                    $sendDataOption = "managedAppsWithOSSharing"
                }
        }

        $obj | Add-Member Noteproperty -Name "sendDataSelector" -Value $sendDataOption

        $obj | Add-Member Noteproperty -Name "overrideFingerprint" -Value ($obj.pinRequiredInsteadOfBiometricTimeout -ne $null)
        $obj | Add-Member Noteproperty -Name "pinReset" -Value ($obj.pinRequiredInsteadOfBiometricTimeout -ne $null)
        $obj | Add-Member Noteproperty -Name "managedBrowserSelection" -Value (?: $obj.customBrowserPackageId  "unmanagedBrowser" $obj.managedBrowser)

        $retValue = $true
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.windowsUpdateForBusinessConfiguration")
    {
        $obj | Add-Member Noteproperty -Name "useDeadLineSettings" -Value ($obj.deadlineForFeatureUpdatesInDays -ne $null -or
                                                                            $obj.deadlineForQualityUpdatesInDays -ne $null -or
                                                                            $obj.deadlineGracePeriodInDays -ne $null -or
                                                                            $obj.postponeRebootUntilAfterDeadline -ne $null)
    
        $retValue = $true
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile")
    {
        $obj | Add-Member Noteproperty -Name "applyDeviceNameTemplate" -Value (?: ([String]::IsNullOrEmpty($obj.deviceNameTemplate)) $false  $true)

        $retValue = $true
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.officeSuiteApp")
    {
        $obj | Add-Member Noteproperty -Name "VersionToInstall" -Value (?: ([String]::IsNullOrEmpty($obj.targetVersion)) (Get-LanguageString "SettingDetails.latest") $obj.targetVersion)

        $obj | Add-Member Noteproperty -Name "useMicrosoftSearchAsDefault" -Value ($obj.excludedApps.bing -eq $false)

        if($obj.officeConfigurationXml)
        {
            $xmlConfig = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($obj.officeConfigurationXml)) 
            $obj | Add-Member Noteproperty -Name "MSAppsConfigXml" -Value $xmlConfig
        }
        $retValue = $true
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.windowsWifiEnterpriseEAPConfiguration")
    {
        if($obj.authenticationMethod -ne "derivedCredential")
        {
            $idCert = Invoke-GraphRequest -URL $obj."identityCertificateForClientAuthentication@odata.navigationLink" -ODataMetadata "minimal" -NoError

            if($idCert.'@OData.Type' -like "*Pkcs*")
            {
                $clientCertType = "PKCS certificate"
            }
            elseif($idCert.'@OData.Type' -like "*SCEP*")
            {
                $clientCertType = "SCEP certificate"
            }

            $obj.authenticationMethod = $clientCertType

            $retValue = $true
        }
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.windows10VpnConfiguration")
    {
        if($obj.windowsInformationProtectionDomain)
        {
            $syntheticWipOrApps = 1
        }
        elseif($obj.onlyAssociatedAppsCanUseConnection)
        {
            $syntheticWipOrApps = 2
        }
        else
        {
            $syntheticWipOrApps = 0
        }
        $obj | Add-Member Noteproperty -Name "syntheticWipOrApps" -Value $syntheticWipOrApps -Force
        
        $retValue = $true
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.iosDeviceFeaturesConfiguration")
    {
        #singleSignOnSettings
        $obj | Add-Member Noteproperty -Name "kerberosPrincipalName" -Value (?? $obj.singleSignOnSettings.kerberosPrincipalName "notConfigured") -Force

        #iosSingleSignOnExtension
        $obj | Add-Member Noteproperty -Name "singleSignOnExtensionType" -Value (?? $obj.iosSingleSignOnExtension."@OData.Type" "notConfigured") -Force

        $retValue = $true
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.macOSDeviceFeaturesConfiguration")
    {
        #macOSSingleSignOnExtension
        $obj | Add-Member Noteproperty -Name "singleSignOnExtensionType" -Value (?? $obj.macOSSingleSignOnExtension."@OData.Type" "notConfigured") -Force

        $retValue = $true
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.windows10EndpointProtectionConfiguration")
    {
        $allowPrintProps = $obj.PSObject.Properties | Where { $_.Name -like "applicationGuardAllowPrint*" }
        $obj | Add-Member Noteproperty -Name "applicationGuardAllowPrinting" -Value (($allowPrintProps | Where Value -eq $true).Count -gt 0)-Force
        $obj | Add-Member Noteproperty -Name "applicationGuardPrintSettings" -Value @(($allowPrintProps | Where Value -eq $true).Name) -Force
        
        $fwProps = $obj.PSObject.Properties | Where { $_.Name -like "firewallIPSecExemptionsAllow*" }
        $obj | Add-Member Noteproperty -Name "firewallSyntheticPresharedKeyEncodingMethod" -Value (($fwProps | Where Value -eq $true).Count -gt 0)-Force
        $obj | Add-Member Noteproperty -Name "firewallSyntheticIPsecExemptions" -Value @(($fwProps | Where Value -eq $true).Name) -Force

        $obj | Add-Member Noteproperty -Name "firewallSyntheticProfileDomainfirewallEnabled" -Value @($obj.firewallProfileDomain -ne $null) -Force
        $obj | Add-Member Noteproperty -Name "firewallSyntheticProfilePrivatefirewallEnabled" -Value @($obj.firewallProfilePrivate -ne $null) -Force
        $obj | Add-Member Noteproperty -Name "firewallSyntheticProfilePublicfirewallEnabled" -Value @($obj.firewallProfilePublic -ne $null) -Force

        Add-DefenderFirewallSettings $obj.firewallProfileDomain "Domain"
        Add-DefenderFirewallSettings $obj.firewallProfilePrivate "Private"
        Add-DefenderFirewallSettings $obj.firewallProfilePublic "Public"

        $obj | Add-Member Noteproperty -Name "bitLockerBaseConfigureEncryptionMethods" -Value (?: ($obj.bitLockerSystemDrivePolicy.encryptionMethod -ne $null) $true $null) -Force
        $obj | Add-Member Noteproperty -Name "bitLockerSystemDriveEncryptionMethod" -Value $obj.bitLockerSystemDrivePolicy.encryptionMethod -Force
        $obj | Add-Member Noteproperty -Name "bitLockerFixedDriveEncryptionMethod" -Value $obj.bitLockerFixedDrivePolicy.encryptionMethod -Force
        $obj | Add-Member Noteproperty -Name "bitLockerRemovableDriveEncryptionMethod" -Value $obj.bitLockerRemovableDrivePolicy.encryptionMethod -Force

        $obj.bitLockerSystemDrivePolicy | Add-Member Noteproperty -Name "bitLockerMinimumPinLength" -Value (?: ($obj.bitLockerSystemDrivePolicy.minimumPinLength -ne $null) $true $null) -Force
        $obj.bitLockerSystemDrivePolicy | Add-Member Noteproperty -Name "bitLockerSyntheticSystemDrivePolicybitLockerDriveRecovery" -Value (?: ($obj.bitLockerSystemDrivePolicy.recoveryOptions -ne $null) $true $null)  -Force
        
        if($obj.bitLockerSystemDrivePolicy.prebootRecoveryUrl -eq $null -and $obj.bitLockerSystemDrivePolicy.prebootRecoveryEnableMessageAndUrl -eq $null)
        {
            $bitLockerPrebootRecoveryMsgURLOption = "default"
        }
        elseif($obj.bitLockerSystemDrivePolicy.prebootRecoveryUrl -eq "" -and $obj.bitLockerSystemDrivePolicy.prebootRecoveryEnableMessageAndUrl -eq "")
        {
            $bitLockerPrebootRecoveryMsgURLOption = "empty"
        }
        elseif($obj.bitLockerSystemDrivePolicy.prebootRecoveryUrl)
        {
            $bitLockerPrebootRecoveryMsgURLOption = "customURL"
        }
        elseif($obj.bitLockerSystemDrivePolicy.prebootRecoveryEnableMessageAndUrl)
        {
            $bitLockerPrebootRecoveryMsgURLOption = "customMessage"
        }

        $obj.bitLockerSystemDrivePolicy | Add-Member Noteproperty -Name "bitLockerPrebootRecoveryMsgURLOption" -Value $bitLockerPrebootRecoveryMsgURLOption -Force
        
        foreach($tmpProp in ($obj.bitLockerSystemDrivePolicy.recoveryOptions.PSObject.Properties).Name)
        {
            $obj.bitLockerSystemDrivePolicy | Add-Member Noteproperty -Name "bitLockerSyntheticSystemDrivePolicy$($tmpProp)" -Value $obj.bitLockerSystemDrivePolicy.recoveryOptions.$tmpProp -Force
        }

        $obj.bitLockerFixedDrivePolicy | Add-Member Noteproperty -Name "bitLockerSyntheticFixedDrivePolicybitLockerDriveRecovery" -Value (?: ($obj.bitLockerFixedDrivePolicy.recoveryOptions -ne $null) $true $null) -Force

        foreach($tmpProp in ($obj.bitLockerFixedDrivePolicy.recoveryOptions.PSObject.Properties).Name)
        {
            $obj.bitLockerFixedDrivePolicy | Add-Member Noteproperty -Name "bitLockerSyntheticFixedDrivePolicy$($tmpProp)" -Value $obj.bitLockerFixedDrivePolicy.recoveryOptions.$tmpProp -Force
        }        

        $obj.bitLockerFixedDrivePolicy | Add-Member Noteproperty -Name "bitLockerSyntheticFixedDrivePolicyrequireEncryptionForWriteAccess" -Value $obj.bitLockerFixedDrivePolicy.requireEncryptionForWriteAccess -Force
        $obj.bitLockerRemovableDrivePolicy | Add-Member Noteproperty -Name "bitLockerSyntheticRemovableDrivePolicyrequireEncryptionForWriteAccess" -Value $obj.bitLockerRemovableDrivePolicy.requireEncryptionForWriteAccess -Force
        
        $appLockerApplicationControlType = "notConfigured"
        if($obj.appLockerApplicationControl -eq "enforceComponentsStoreAppsAndSmartlocker")
        {
            $appLockerApplicationControlType = "allow"
        }
        if($obj.appLockerApplicationControl -eq "auditComponentsAndStoreApps")
        {
            $appLockerApplicationControlType = "audit"
        }
        $obj | Add-Member Noteproperty -Name "appLockerApplicationControlType" -Value $appLockerApplicationControlType -Force

        $retValue = $true
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.iosGeneralDeviceConfiguration")
    {
        if([String]::IsNullOrEmpty($obj.KioskModeAppTypeDropDown))
        {
            $kioskMode = $null
            if($obj.kioskModeAppStoreUrl)
            {
                $kioskMode = 0
            }
            elseif($obj.kioskModeManagedAppId)
            {
                $kioskMode = 1
            }
            elseif($obj.kioskModeBuiltInAppId)
            {
                $kioskMode = 2
            }
            if($kioskMode -ne $null)
            {
                $obj | Add-Member Noteproperty -Name "KioskModeAppTypeDropDown" -Value $kioskMode -Force 
            }
        }

        $MediaContentRatingRegionSelectorDropDown = "notConfigured"
        foreach($mediaRatingProp in ($obj.PSObject.Properties | Where { $_.Name -like "mediaContentRating*" -and $_.Name -notlike "*@odata.type" -and $_.Name -ne "mediaContentRatingApps"}).Name)
        {
            if($obj.$mediaRatingProp -ne $null)
            {
                $MediaContentRatingRegionSelectorDropDown = $mediaRatingProp
                break
            }
        }
        $obj | Add-Member Noteproperty -Name "MediaContentRatingRegionSelectorDropDown" -Value $MediaContentRatingRegionSelectorDropDown -Force

        $networkUsageRulesCellularDataBlockType = "none"
        $networkUsageRulesCellularRoamingDataBlockType = "none"

        $tmpRule = $obj.networkUsageRules | Where cellularDataBlocked -eq $true
        if($tmpRule)
        {
            $networkUsageRulesCellularDataBlockType = ?: ($tmpRule.managedApps) "choose" "all"
            $obj | Add-Member Noteproperty -Name "networkUsageRulesCellularDataList" -Value ($tmpRule.managedApps -join $objSeparator) -Force
        }
        $tmpRule = $obj.networkUsageRules | Where cellularDataBlockWhenRoaming -eq $true
        if($tmpRule)
        {
            $networkUsageRulesCellularRoamingDataBlockType = ?: ($tmpRule.managedApps) "choose" "all"

            $obj | Add-Member Noteproperty -Name "networkUsageRulesCellularRoamingDataList" -Value $tmpRule.managedApps -Force
        }
        $obj | Add-Member Noteproperty -Name "networkUsageRulesCellularDataBlockType" -Value $networkUsageRulesCellularDataBlockType -Force
        $obj | Add-Member Noteproperty -Name "networkUsageRulesCellularRoamingDataBlockType" -Value $networkUsageRulesCellularRoamingDataBlockType -Force

        $retValue = $true
    }    
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.macOSEndpointProtectionConfiguration")
    {
        $firewallAllowedApps = $obj.firewallApplications | Where allowsIncomingConnections -eq $true
        $firewallBlockedApps = $obj.firewallApplications | Where allowsIncomingConnections -eq $false

        $obj | Add-Member Noteproperty -Name "firewallAllowedApps" -Value $firewallAllowedApps
        $obj | Add-Member Noteproperty -Name "firewallBlockedApps" -Value $firewallBlockedApps

        $retValue = $true
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.windowsFeatureUpdateProfile")
    {
        if(-not $script:win10FeatureUpdates)
        {
            $script:win10FeatureUpdates = (Invoke-GraphRequest -URL "/deviceManagement/windowsUpdateCatalogItems/microsoft.graph.windowsFeatureUpdateCatalogItem").value
        }

        $verInfo = $script:win10FeatureUpdates | Where version -eq $obj.featureUpdateVersion

        if($verInfo)
        {
            $verInfoTxt = $verInfo.displayName
        }
        else
        {
            $verInfoTxt = "{0} ({1})" -f $obj.featureUpdateVersion,(Get-LanguageString "WindowsFeatureUpdate.EndOFSupportStatus.notSupported")
        }

        $obj | Add-Member Noteproperty -Name "featureUpdateDisplayName" -Value $verInfoTxt

        $retValue = $true
    }    
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.iosUpdateConfiguration")
    {
        if(-not $script:iOSAvailableUpdateVersions)
        {
            $script:iOSAvailableUpdateVersions = (Invoke-GraphRequest -URL "/deviceManagement/deviceConfigurations/getIosAvailableUpdateVersions").value
            $script:iOSAvailableUpdateVersions = $script:iOSAvailableUpdateVersions | Sort -property productVersion -Descending
        }

        $verInfo = $script:iOSAvailableUpdateVersions | Where productVersion -eq $obj.desiredOsVersion

        $versionText = "{0} {1}" -f (Get-LanguageString "SoftwareUpdates.IosUpdatePolicy.Settings.IOSVersion.prefix"), $obj.desiredOsVersion
        if(-not $verInfo)
        {
            $versionText = "$versionText ($(Get-LanguageString "SoftwareUpdates.IosUpdatePolicy.Settings.IOSVersion.noLongerSupported"))"
        }
        elseif($verInfo[0].productVersion -eq $obj.desiredOsVersion)
        {
            $versionText = "$versionText ($(Get-LanguageString "SoftwareUpdates.IosUpdatePolicy.Settings.IOSVersion.latestUpdate"))"
        }
        $obj | Add-Member Noteproperty -Name "versionInfo" -Value $versionText

        $timeWidows = @()
        foreach($timeWindow in $obj.customUpdateTimeWindows)
        {
            $startDay = Get-LanguageString "SettingDetails.$($timeWindow.startDay)"
            $endDay = Get-LanguageString "SettingDetails.$($timeWindow.endDay)"
            for($i = 0;$i -lt 2;$i++)
            {
                if($i -eq 0)
                {
                    $hour=[int]$timeWindow.startTime.Split(":")[0]
                }
                else
                {
                    $hour=[int]$timeWindow.endTime.Split(":")[0]
                }

                if($hour -gt 12)
                {
                    $when = "PM"
                    $hour = $hour - 12
                }
                else
                {
                    $when = "AM"
                }
                if($hour -eq 0) { $hourStr = "twelve" }
                elseif($hour -eq 1) { $hourStr = "one" }
                elseif($hour -eq 2) { $hourStr = "two" }
                elseif($hour -eq 3) { $hourStr = "three" }
                elseif($hour -eq 4) { $hourStr = "four" }
                elseif($hour -eq 5) { $hourStr = "five" }
                elseif($hour -eq 6) { $hourStr = "six" }
                elseif($hour -eq 7) { $hourStr = "seven" }
                elseif($hour -eq 8) { $hourStr = "eight" }
                elseif($hour -eq 9) { $hourStr = "nine" }
                elseif($hour -eq 10) { $hourStr = "ten" }
                elseif($hour -eq 11) { $hourStr = "eleven" }

                if($i -eq 0)
                {
                    $startTime = Get-LanguageString "SettingDetails.$($hourStr)$($when)Option"
                }
                else
                {
                    $endTime = Get-LanguageString "SettingDetails.$($hourStr)$($when)Option"
                }                
            }
            $timeWidows += ($startDay + $propSeparator + $startTime + $propSeparator + $endDay + $propSeparator + $endTime)
        }
        $obj | Add-Member Noteproperty -Name "timeWidows" -Value ($timeWidows -join $objSeparator)
    } 
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration")
    {
        if($obj.selectedMobileAppIds.Count -eq 0)
        {
            $apps = Get-LanguageString "EnrollmentStatusScreen.Apps.useSelectedAppsAll"
        }
        else
        {
            $allApps = Get-CDAllTenantApps
            $appsArr = @()
            foreach($appId in $obj.selectedMobileAppIds)
            {
                $tmpApp = $allApps | Where Id -eq $appId
                if($tmpApp)
                {
                    $appsArr += $tmpApp.displayName
                }
                else
                {
                    Write-Log "No app found with id $appId" 3
                }
            }
            $apps = $appsArr -join $objSeparator
        }
        $obj | Add-Member Noteproperty -Name "showCustomErrorMessage" -Value (-not [string]::IsNullOrEmpty($obj.customErrorMessage))
        $obj | Add-Member Noteproperty -Name "waitForApps" -Value $apps
    }
    elseif($obj.'@OData.Type' -like "#microsoft.graph.win32LobApp")
    {
        $requirementRulesSummary = @()
        $detectionRulesSummary = @()
        $returnCodes = @()
        foreach($rc in $obj.returnCodes)
        {
            $returnCodes += ("{0} {1}" -f @($rc.returnCode,(Get-LanguageString "Win32ReturnCodes.CodeTypes.$($rc.type)")))
        }

        $dependencyApps = @()
        $supersededApps = @()
        if($obj.dependentAppCount -gt 0 -or $obj.supersededAppCount -gt 0)
        {
            $relationships = (Invoke-GraphRequest -Url "/deviceAppManagement/mobileApps/$($obj.Id)/relationships?`$filter=targetType%20eq%20microsoft.graph.mobileAppRelationshipType%27child%27").value
            foreach($rel in $relationships)
            {
                if($rel."@odata.type" -eq "#microsoft.graph.mobileAppDependency")
                {
                    $dependencyApps += ("{0} {1}" -f @($rel.targetDisplayName,(Get-LanguageString "SettingDetails.$((?: ($rel.dependencyType -eq "autoInstall") "win32DependenciesAutoInstall" "win32DependenciesDetect"))")))
                }
                elseif($rel."@odata.type" -eq "#microsoft.graph.mobileAppSupersedence")
                {
                    $supersededApps += ("{0} {1}" -f @($rel.targetDisplayName,(Get-LanguageString "SettingDetails.$((?: ($rel.supersedenceType -eq "update") "win32SupersedenceUpdate" "win32SupersedenceReplace"))")))
                }
            }
        }

        foreach($rule in $obj.requirementRules)
        {
            if($rule.'@OData.Type' -eq "#microsoft.graph.win32LobAppFileSystemRequirement")
            {
                $lngId = "fileType"
                $textValue = $rule.path
            }
            elseif($rule.'@OData.Type' -eq "#microsoft.graph.win32LobAppRegistryRequirement")
            {
                $lngId = "registry"
                $textValue = $rule.keyPath
            }
            else #win32LobAppProductCodeDetection
            {
                $lngId = "script"
                $textValue = $rule.displayName
            }
            $requirementRulesSummary += ("{0} {1}" -f @((Get-LanguageString "Win32Requirements.AdditionalRequirements.RequirementTypeOptions.$lngId"),$textValue))
        }

        if(($obj.detectionRules | Where '@OData.Type' -eq "#microsoft.graph.win32LobAppPowerShellScriptDetection"))
        {
            $detectionRulesType = Get-LanguageString "DetectionRules.RuleConfigurationOptions.customScript"
        }
        else
        {
            $detectionRulesType = Get-LanguageString "DetectionRules.RuleConfigurationOptions.manual"
            foreach($rule in $obj.detectionRules)
            {
                if($rule.'@OData.Type' -eq "#microsoft.graph.win32LobAppFileSystemDetection")
                {
                    $lngId = "file"
                    $textValue = $rule.path
                }
                elseif($rule.'@OData.Type' -eq "#microsoft.graph.win32LobAppRegistryDetection")
                {
                    $lngId = "registry"
                    $textValue = $rule.keyPath
                }
                else #win32LobAppProductCodeDetection
                {
                    $lngId = "mSI"
                    $textValue = $rule.productCode
                }
                $detectionRulesSummary += ("{0} {1}" -f @((Get-LanguageString "DetectionRules.Manual.RuleTypeOptions.$lngId"),$textValue))
            }
        }
        $obj | Add-Member Noteproperty -Name "requirementRulesSummary" -Value ($requirementRulesSummary -join $objSeparator) -Force 
        $obj | Add-Member Noteproperty -Name "detectionRulesSummary" -Value ($detectionRulesSummary -join $objSeparator) -Force 
        $obj | Add-Member Noteproperty -Name "dependencyApps" -Value ($dependencyApps -join $objSeparator) -Force 
        $obj | Add-Member Noteproperty -Name "supersededApps" -Value ($supersededApps -join $objSeparator) -Force 
        $obj | Add-Member Noteproperty -Name "detectionRulesType" -Value $detectionRulesType -Force 
        $obj | Add-Member Noteproperty -Name "returnCodes" -Value ($returnCodes -join $objSeparator) -Force 
        $obj | Add-Member Noteproperty -Name "win10Release" -Value (Get-LanguageString "MinimumOperatingSystem.Windows.V10Release.release$($obj.minimumSupportedWindowsRelease)") -Force 
    }
    elseif($obj.'@OData.Type' -eq "#microsoft.graph.deviceHealthScript")
    {
        $obj | Add-Member Noteproperty -Name "detectionScriptAdded" -Value (-not [String]::IsNullOrEmpty($obj.detectionScriptContent))
        $obj | Add-Member Noteproperty -Name "remediationScriptAdded" -Value (-not [String]::IsNullOrEmpty($obj.remediationScriptContent))
        $obj | Add-Member Noteproperty -Name "useLoggedOnCredentials" -Value ($obj.runAsAccount -ne "system")

        if($obj.detectionScriptContent)
        {
            $obj | Add-Member Noteproperty -Name "detectionScriptContentString" -Value ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($obj.detectionScriptContent))))
        }
        if($obj.remediationScriptContent)
        {
            $obj | Add-Member Noteproperty -Name "remediationScriptContentString" -Value ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($obj.remediationScriptContent))))
        }

    }

    if(($obj.PSObject.Properties | where Name -eq "securityRequireSafetyNetAttestationBasicIntegrity") -and 
    ($obj.PSObject.Properties | where Name -eq "securityRequireSafetyNetAttestationCertifiedDevice"))
    {
        $androidSafetyNetAttestationOptions = "notConfigured"
        if($obj.securityRequireSafetyNetAttestationBasicIntegrity -eq $true -and 
        $obj.securityRequireSafetyNetAttestationCertifiedDevice -eq $true)
        {
            $androidSafetyNetAttestationOptions = 'basicIntegrityAndCertified'
        }
        elseif($obj.securityRequireSafetyNetAttestationBasicIntegrity -eq $true)
        {
            $androidSafetyNetAttestationOptions = 'basicIntegrity'
        }
        $obj | Add-Member Noteproperty -Name "androidSafetyNetAttestationOptions" -Value $androidSafetyNetAttestationOptions -Force

        $retValue = $true
    }
    
    if(($obj.PSObject.Properties | Where Name -eq "periodOfflineBeforeWipeIsEnforced"))
    {
        #Conditional Launch settings for AppProtection policies

        $conditionalLaunch = @()

        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "maxPinAttempts" "maximumPinRetries" (?: ($obj.appActionIfMaximumPinRetriesExceeded -eq "block") "resetPin" "wipeData"))
        
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "offlineGracePeriod" "periodOfflineBeforeAccessCheck" "blockMinutes")
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "offlineGracePeriod" "periodOfflineBeforeWipeIsEnforced" "wipeDays")

        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "minAppVersion" "minimumWipeAppVersion" "wipeData")
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "minAppVersion" "minimumRequiredAppVersion" "blockAccess")
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "minAppVersion" "minimumWarningAppVersion" "warn")
        
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "minSdkVersion" "minimumRequiredSdkVersion" "blockAccess")
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "minSdkVersion" "minimumWipeSdkVersion" "wipeData")

        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "onlineButUnableToCheckin" "appActionIfUnableToAuthenticateUser" (?: ($obj.appActionIfUnableToAuthenticateUser -eq "block") "blockAccess" "wipeData") -SkipValue) 

        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "jailbrokenRootedDevices" "appActionIfDeviceComplianceRequired" (?: ($obj.appActionIfDeviceComplianceRequired -eq "block") "blockAccess" "wipeData") -SkipValue) 

        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "minOSVersion" "minimumWipeOsVersion" "wipeData")
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "minOSVersion" "minimumRequiredOsVersion" "blockAccess")
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "minOSVersion" "minimumWarningOsVersion" "warn")

        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "maxOSVersion" "maximumWipeOsVersion" "wipeData")
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "maxOSVersion" "maximumRequiredOsVersion" "blockAccess")
        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "maxOSVersion" "maximumWarningOsVersion" "warn")

        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "deviceModels" "allowedIosDeviceModels" (?: ($obj.appActionIfIosDeviceModelNotAllowed -eq "block") "allowSpecifiedBlock" "allowSpecifiedWipe")) 

        $conditionalLaunch += (Get-ConditionalLaunchSetting $obj "maximumAllowedDeviceThreatLevel" "maximumAllowedDeviceThreatLevel" (?: ($obj.appActionIfDeviceComplianceRequired -eq "block") "blockAccess" "wipeData")) 

        if($conditionalLaunch.Count -gt 0)
        {
            $obj | Add-Member Noteproperty -Name "ConditionalLaunchSettings" -Value @($conditionalLaunch)
        }

        $retValue = $true
    }

    return $retValue
}

# App Config
function Invoke-CDDocumentiosMobileAppConfiguration
{
    param($documentationObj)

    $obj = $documentationObj.Object
    $objectType = $documentationObj.ObjectType

    $script:objectSeparator = ?? $global:cbDocumentationObjectSeparator.SelectedValue ([System.Environment]::NewLine)
    $script:propertySeparator = ?? $global:cbDocumentationPropertySeparator.SelectedValue ","
    
    ###################################################
    # Basic info
    ###################################################

    Add-BasicDefaultValues $obj $objectType
    Add-BasicPropertyValue (Get-LanguageString "TableHeaders.configurationType") (Get-LanguageString "SettingDetails.appConfiguration")
    Add-BasicPropertyValue (Get-LanguageString "Inputs.enrollmentTypeLabel") (Get-LanguageString "EnrollmentType.devicesWithEnrollment")
    
    $platformId = Get-ObjectPlatformFromType $obj
    Add-BasicPropertyValue (Get-LanguageString "Inputs.platformLabel") (Get-LanguageString "Platform.$platformId")

    $allApps = Get-CDAllTenantApps
    $appsList = @()
    foreach($id in ($obj.targetedMobileApps))
    {
        $tmpApp = $allApps | Where Id -eq $id
        $appsList += ?? $tmpApp.displayName $id
    }

    Add-BasicPropertyValue (Get-LanguageString "SettingDetails.targetedAppLabel") ($appsList -join $objSeparator)
    
    Add-BasicAdditionalValues  $obj $objectType
    
    $category = Get-LanguageString "TableHeaders.settings"

    if($obj.encodedSettingXml)
    {
        $xml = $null
        try
        {
            $xml = [xml]([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($obj.encodedSettingXml)))
        }
        catch
        {
            Write-LogError "Failed to convert XML data to XML" $_.Exception
            return
        }

        for($i = 0;$i -lt $xml.dict.ChildNodes.Count;$i++)
        {
            $name = $xml.dict.ChildNodes[$i].'#text'
            $i++
            $value = $xml.dict.ChildNodes[$i].'#text'

            Add-CustomSettingObject ([PSCustomObject]@{
                Name = $name
                Value = $value
                EntityKey = $name
                Category = $category
            })             
        }     
    }
    else 
    {
        # Not the best way. BundleId should be used but then full app info is required
        if(($obj.settings | Where { $_.appConfigKey -like "com.microsoft.outlook*" }))
        {
            if([IO.File]::Exists(($global:AppRootFolder + "\Documentation\ObjectInfo\#AppConfigOutlookDevice.json")))
            {
                $tmp = $obj.settings | Where { $_.appConfigKey -eq "com.microsoft.outlook.EmailProfile.AccountType" }
                if($tmp){ $configEmail=$true }else{ $configEmail=$false }
                $outlookSettings = [PSCustomObject]@{
                    configureEmail = $configEmail
                }
                foreach($setting in $obj.settings)
                {
                    if($setting.appConfigKeyType -eq "booleanType")
                    {
                        $value = $setting.appConfigKeyValue -eq "true"
                    }
                    else
                    {
                        $value = $setting.appConfigKeyValue
                    }
                    $outlookSettings | Add-Member Noteproperty -Name $setting.appConfigKey -Value $value -Force
                }

                $jsonObj = Get-Content ($global:AppRootFolder + "\Documentation\ObjectInfo\#AppConfigOutlookDevice.json") | ConvertFrom-Json
                Invoke-TranslateSection $outlookSettings $jsonObj
            }
        }                
        
        $addedSettings = Get-DocumentedSettings

        foreach($setting in $obj.settings)
        {
            if(($addedSettings | Where EntityKey -eq $setting.appConfigKey)) { continue }

            Add-CustomSettingObject ([PSCustomObject]@{
                Name = $setting.appConfigKey
                Value = $setting.appConfigKeyValue
                EntityKey = $setting.appConfigKey
                Category = Get-LanguageString "TACSettings.generalSettings"
                SubCategory = Get-LanguageString "SettingDetails.additionalConfiguration"
            })
        }
    }
}

function Invoke-CDDocumentManagedAppConfig
{
    param($documentationObj)

    $obj = $documentationObj.Object
    $objectType = $documentationObj.ObjectType

    $script:objectSeparator = ?? $global:cbDocumentationObjectSeparator.SelectedValue ([System.Environment]::NewLine)
    $script:propertySeparator = ?? $global:cbDocumentationPropertySeparator.SelectedValue ","
    
    ###################################################
    # Basic info
    ###################################################

    Add-BasicDefaultValues $obj $objectType
    Add-BasicPropertyValue (Get-LanguageString "TableHeaders.configurationType") (Get-LanguageString "SettingDetails.appConfiguration")
    
    $customApps,$publishedApps = Get-CDMobileApps $obj.Apps

    Add-BasicPropertyValue (Get-LanguageString "Inputs.enrollmentTypeLabel") (Get-LanguageString "EnrollmentType.devicesWithoutEnrollment")
    Add-BasicPropertyValue (Get-LanguageString "SettingDetails.publicApps") ($publishedApps -join  $script:objectSeparator)
    Add-BasicPropertyValue (Get-LanguageString "SettingDetails.customApps") ($customApps -join  $script:objectSeparator)

    Add-BasicAdditionalValues  $obj $objectType

    $addedSettings = @()

    $appSettings = [PSCustomObject]@{ }
    foreach($setting in $obj.customSettings)
    {
        $appSettings | Add-Member Noteproperty -Name $setting.name -Value $setting.value -Force
    }

    if(($obj.Apps | Where { $_.mobileAppIdentifier.packageId -eq "com.microsoft.office.outlook" }))
    {
        if([IO.File]::Exists(($global:AppRootFolder + "\Documentation\ObjectInfo\#AppConfigOutlookApp.json")))
        {
            $jsonObj = Get-Content ($global:AppRootFolder + "\Documentation\ObjectInfo\#AppConfigOutlookApp.json") | ConvertFrom-Json
            Invoke-TranslateSection $appSettings $jsonObj
        }
    }

    if(($obj.Apps | Where { $_.mobileAppIdentifier.bundleId -like "com.microsoft.msedge" }))
    {
        if($appSettings.'com.microsoft.intune.mam.managedbrowser.bookmarks')
        {
            $appSettings.'com.microsoft.intune.mam.managedbrowser.bookmarks' = $appSettings.'com.microsoft.intune.mam.managedbrowser.bookmarks'.Replace("||",$script:objectSeparator).Replace("|",$script:propertySeparator)
        }

        if($appSettings.'com.microsoft.intune.mam.managedbrowser.AllowListURLs')
        {
            $appSettings.'com.microsoft.intune.mam.managedbrowser.AllowListURLs' = $appSettings.'com.microsoft.intune.mam.managedbrowser.AllowListURLs'.Replace("|",$script:objectSeparator)
        }

        if($appSettings.'com.microsoft.intune.mam.managedbrowser.BlockListURLs')
        {
            $appSettings.'com.microsoft.intune.mam.managedbrowser.BlockListURLs' = $appSettings.'com.microsoft.intune.mam.managedbrowser.BlockListURLs'.Replace("|",$script:objectSeparator)
        }

        if([IO.File]::Exists(($global:AppRootFolder + "\Documentation\ObjectInfo\#AppConfigEdgeApp.json")))
        {
            $jsonObj = Get-Content ($global:AppRootFolder + "\Documentation\ObjectInfo\#AppConfigEdgeApp.json") | ConvertFrom-Json
            Invoke-TranslateSection $appSettings $jsonObj
        }
    }

    $addedSettings = Get-DocumentedSettings

    $category = Get-LanguageString "TACSettings.generalSettings" 

    foreach($setting in $obj.customSettings)
    {
        if(($addedSettings | Where EntityKey -eq $setting.name)) { continue }

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $setting.name
            Value = $setting.value
            EntityKey = $setting.name
            Category = $category
        })
    }       
}

# Document Named locations
function Invoke-CDDocumentCountryNamedLocation
{
    param($documentationObj)

    $obj = $documentationObj.Object
    $objectType = $documentationObj.ObjectType

    $script:objectSeparator = ?? $global:cbDocumentationObjectSeparator.SelectedValue ([System.Environment]::NewLine)
    $script:propertySeparator = ?? $global:cbDocumentationPropertySeparator.SelectedValue ","
    
    ###################################################
    # Basic info
    ###################################################

    Add-BasicDefaultValues $obj $objectType
    Add-BasicPropertyValue (Get-LanguageString "TableHeaders.configurationType") (Get-LanguageString "AzureIAM.menuItemNamedNetworks")
    Add-BasicAdditionalValues  $obj $objectType
    
    Add-CustomSettingObject ([PSCustomObject]@{
        Name = Get-LanguageString "AzureIAM.NamedLocation.Form.CountryLookup.ariaLabel"
        Value = Get-LanguageString "AzureIAM.NamedLocation.Form.CountryLookup.$((?: ($obj.countryLookupMethod -eq "clientIpAddress") "ip" "gps"))"
        EntityKey = "countryLookupMethod"
    })

    Add-CustomSettingObject ([PSCustomObject]@{
        Name = Get-LanguageString "AzureIAM.NamedLocation.Form.Include.label"
        Value = Get-LanguageString (?: ($obj.includeUnknownCountriesAndRegions -eq $true) "Inputs.enabled" "Inputs.disabled")
        EntityKey = "includeUnknownCountriesAndRegions"
    })        

    $countryList = @()
    foreach($country in $obj.countriesAndRegions)
    {
        $countryList += Get-LanguageString "Countries.$($country.ToLower())"
    }

    Add-CustomSettingObject ([PSCustomObject]@{
        Name = Get-LanguageString "AzureIAM.NamedLocation.Type.countries"
        Value = $countryList -join $script:objectSeparator
        EntityKey = "countriesAndRegions"
    })         
}

function Invoke-CDDocumentIPNamedLocation
{
    param($documentationObj)

    $obj = $documentationObj.Object
    $objectType = $documentationObj.ObjectType

    $script:objectSeparator = ?? $global:cbDocumentationObjectSeparator.SelectedValue ([System.Environment]::NewLine)
    $script:propertySeparator = ?? $global:cbDocumentationPropertySeparator.SelectedValue ","
    
    ###################################################
    # Basic info
    ###################################################

    Add-BasicDefaultValues $obj $objectType
    Add-BasicPropertyValue (Get-LanguageString "TableHeaders.configurationType") (Get-LanguageString "AzureIAM.menuItemNamedNetworks")
    Add-BasicAdditionalValues  $obj $objectType

    Add-CustomSettingObject ([PSCustomObject]@{
        Name = Get-LanguageString "AzureIAM.NamedLocation.Form.Trusted.label"
        Value = Get-LanguageString (?: ($obj.isTrusted -eq $true) "Inputs.enabled" "Inputs.disabled")
        EntityKey = "isTrusted"
    })        

    $ipList = @()
    foreach($ip in $obj.ipRanges)
    {
        $ipList += $ip.cidrAddress
    }

    Add-CustomSettingObject ([PSCustomObject]@{
        Name = Get-LanguageString "AzureIAM.NamedLocation.Type.ipRanges"
        Value = $ipList -join $script:objectSeparator
        EntityKey = "ipRanges"
    })         
}

# Document Conditional Access policy
function Invoke-CDDocumentConditionalAccess
{
    param($documentationObj)

    $obj = $documentationObj.Object
    $objectType = $documentationObj.ObjectType

    $script:objectSeparator = ?? $global:cbDocumentationObjectSeparator.SelectedValue ([System.Environment]::NewLine)
    $script:propertySeparator = ?? $global:cbDocumentationPropertySeparator.SelectedValue ","
    
    ###################################################
    # Basic info
    ###################################################

    Add-BasicDefaultValues $obj $objectType

    if($obj.state -eq "enabledForReportingButNotEnforced")
    {
        $state = Get-LanguageString "AzureIAM.PolicyState.reportOnly"
    }
    elseif($obj.state -eq "disabled")
    {
        $state = Get-LanguageString "AzureIAM.PolicyState.off"
    }
    else
    {
        $state = Get-LanguageString "AzureIAM.PolicyState.on"
    }

    Add-BasicPropertyValue (Get-LanguageString "AzureIAM.policyEnforceLabel") $state

    Add-BasicAdditionalValues  $obj $objectType

    ###################################################
    # User and groups
    ###################################################

    $ids = @()
    foreach($id in ($obj.conditions.users.includeUsers + $obj.conditions.users.includeGroups + $obj.conditions.users.excludeUsers + $obj.conditions.users.excludeGroups))
    {
        if($id -in $ids) { continue }
        elseif($id -eq "GuestsOrExternalUsers") { continue }
        elseif($id -eq "All") { continue }
        elseif($id -eq "None") { continue }
        
        $ids += $id
    }    

    $roleIds = @()
    foreach($id in ($obj.conditions.users.includeRoles + $obj.conditions.users.excludeRoles))
    {
        if($id -in $ids) { continue }
        $roleIds += $id
    }
    
    $idInfo = $null

    if($ids.Count -gt 0)
    {
        $ht = @{}
        $ht.Add("ids", @($ids | Unique))

        $body = $ht | ConvertTo-Json

        $idInfo = (Invoke-GraphRequest -Url "/directoryObjects/getByIds?`$select=displayName,id" -Content $body -Method "Post").Value
    }

    if($roleIds.Count -gt 0 -and -not $script:allAadRoles)
    {
        $script:allAadRoles =(Invoke-GraphRequest -url "/directoryRoleTemplates?`$select=Id,displayName" -ODataMetadata "minimal").value
    }

    $includeLabel = Get-LanguageString "AzureIAM.userSelectionBladeIncludeTabTitle"
    $excludeLabel = Get-LanguageString "AzureIAM.userSelectionBladeExcludeTabTitle"

    $category = Get-LanguageString "AzureIAM.usersGroupsLabel"

    if((($obj.conditions.users.includeUsers | Where { $_ -eq "All"}) -ne $null))
    {
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value = Get-LanguageString "AzureIAM.allUsersString"
            Category = $category
            SubCategory = $includeLabel
            EntityKey = "includeUsers"
        })        
    }
    elseif((($obj.conditions.users.includeUsers | Where { $_ -eq "None"}) -ne $null))
    {
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value = Get-LanguageString "AzureIAM.chooseApplicationsNone"
            Category = $category
            SubCategory = $includeLabel
            EntityKey = "includeUsers"
        })        
    }
    else
    {
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value = Get-LanguageString "AzureIAM.userSelectionBladeSelectedUsers"
            Category = $category
            SubCategory = $includeLabel
            EntityKey = "includeUsers"
        })  

        if((($obj.conditions.users.includeUsers | Where { $_ -eq "GuestsOrExternalUsers"}) -ne $null))
        {
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = Get-LanguageString "AzureIAM.allGuestUserLabel"
                Value = Get-LanguageString "Inputs.enabled" #$((?: (($obj.conditions.users.includeUsers | Where { $_ -eq "GuestsOrExternalUsers"}) -ne $null) "enabled" "disabled"))"
                Category = $category
                SubCategory = $includeLabel
                EntityKey = "includeGuestsOrExternalUsers"
            })
        }

        if($obj.conditions.users.includeRoles.Count -gt 0)
        {
            $tmpObjs = @() 
            foreach($id in $obj.conditions.users.includeRoles)
            {
                $idObj = $script:allAadRoles | Where Id -eq $id
                $tmpObjs += ?? $idObj.displayName $id
            }

            Add-CustomSettingObject ([PSCustomObject]@{
                Name = Get-LanguageString "AzureIAM.directoryRolesLabel"
                Value = $tmpObjs -join $script:objectSeparator
                Category = $category
                SubCategory = $includeLabel
                EntityKey = "includeRoles"
            })
        }

        if(($obj.conditions.users.includeUsers + $obj.conditions.users.includeGroups).Count -gt 0)
        {
            $tmpObjs = @() 
            foreach($id in ($obj.conditions.users.includeUsers + $obj.conditions.users.includeGroups))
            {
                if($id -eq "GuestsOrExternalUsers") { continue }
                $idObj = $idInfo | Where Id -eq $id
                $tmpObjs += ?? $idObj.displayName $id
            }
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = $category
                Value = $tmpObjs -join $script:objectSeparator
                Category = $category
                SubCategory = $includeLabel
                EntityKey = "includeUsersGroups"
            })
        }
    }
    
    if((($obj.conditions.users.excludeUsers | Where { $_ -eq "GuestsOrExternalUsers"}) -ne $null))
    {
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = Get-LanguageString "AzureIAM.allGuestUserLabel"
            Value = Get-LanguageString "Inputs.enabled" #$((?: (($obj.conditions.users.excludeUsers | Where { $_ -eq "GuestsOrExternalUsers"}) -ne $null) "enabled" "disabled"))"
            Category = $category
            SubCategory = $excludeLabel
            EntityKey = "excludeGuestsOrExternalUsers"
        })
    }

    if($obj.conditions.users.excludeRoles.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in $obj.conditions.users.excludeRoles)
        {
            $idObj = $script:allAadRoles | Where Id -eq $id
            $tmpObjs += ?? $idObj.displayName $id
        }

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = Get-LanguageString "AzureIAM.directoryRolesLabel"
            Value = $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = $excludeLabel
            EntityKey = "excludeRoles"
        })
    }

    if(($obj.conditions.users.excludeUsers + $obj.conditions.users.excludeGroups).Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.users.excludeUsers + $obj.conditions.users.excludeGroups))
        {
            if($id -eq "GuestsOrExternalUsers") { continue }
            $idObj = $idInfo | Where Id -eq $id
            $tmpObjs += ?? $idObj.displayName $id
        }
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $category
            Value = $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = $excludeLabel
            EntityKey = "excludeUsersGroups"
        })
    }

    ###################################################
    # Cloud apps or actions
    ###################################################

    $category = Get-LanguageString "AzureIAM.UserActions.appsOrActionsTitle"
    $cloudAppsLabel = Get-LanguageString "AzureIAM.policyCloudAppsLabel"    
    
    $cloudApps = Get-CDAllCloudApps
    
    if((($obj.conditions.applications.includeApplications | Where { $_ -eq "All"}) -ne $null))
    {
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value = Get-LanguageString "AzureIAM.cloudappsSelectionBladeAllCloudapps" #Get-LanguageString "Inputs.enabled"
            Category = $category
            SubCategory = $cloudAppsLabel
            EntityKey = "includeApplications"
        })        
    }
    elseif((($obj.conditions.applications.excludeApplications | Where { $_ -eq "None"}) -ne $null))
    {
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value = Get-LanguageString "AzureIAM.chooseApplicationsNone" #Get-LanguageString "Inputs.enabled"
            Category = $category
            SubCategory = $cloudAppsLabel
            EntityKey = "includeApplications"
        })        
    }
    elseif($obj.conditions.applications.includeApplications.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.applications.includeApplications))
        {
            $idObj = $cloudApps | Where AppId -eq $id
            $tmpObjs += ?? $idObj.displayName $id
        }
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value = $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = $cloudAppsLabel 
            EntityKey = "includeApplications"
        })        
    }    

    if($obj.conditions.applications.excludeApplications.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.applications.excludeApplications))
        {
            $idObj = $cloudApps | Where AppId -eq $id
            $tmpObjs += ?? $idObj.displayName $id
        }
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $excludeLabel
            Value = $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = $cloudAppsLabel 
            EntityKey = "excludeApplications"
        })        
    }  

    if($obj.conditions.applications.includeUserActions.Count -gt 0)
    {
        $userActionsLabel = Get-LanguageString "AzureIAM.UserActions.label"
        if(($obj.conditions.applications.includeUserActions | Where { $_ -eq "urn:user:registersecurityinfo" }))
        {
            $value =  Get-LanguageString "AzureIAM.UserActions.registerSecurityInfo"
        }
        else
        {
            $value =  Get-LanguageString "AzureIAM.UserActions.registerOrJoinDevices"
        }

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value =  $value
            Category = $category
            SubCategory = $userActionsLabel
            EntityKey = "includeUserActions"
        })           
    }

    if($obj.conditions.applications.includeAuthenticationContextClassReferences.Count -gt 0)
    {
        # Fix better text
        $userActionsLabel = Get-LanguageString "AzureIAM.AuthContext.label"
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.applications.includeAuthenticationContextClassReferences))
        {
            $tmpObjs += $id
        }        

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value =  $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = $userActionsLabel
            EntityKey = "includeAuthenticationContextClassReferences"
        })           
    }

    ###################################################
    # Conditions
    ###################################################

    $category = Get-LanguageString "AzureIAM.helpConditionsTitle"

    #$category = Get-LanguageString "AzureIAM.policyConditionUserRisk"

    if($obj.conditions.userRiskLevels.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.userRiskLevels))
        {
            $tmpObjs += Get-LanguageString "AzureIAM.$($id)Risk"
        }        

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value =  $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = Get-LanguageString "AzureIAM.policyConditionUserRisk"
            EntityKey = "userRiskLevels"
        })           
    }

    if($obj.conditions.signInRiskLevels.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.signInRiskLevels))
        {
            $tmpObjs += Get-LanguageString "AzureIAM.$($id)Risk"
        }        

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value =  $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = Get-LanguageString "AzureIAM.policyConditionSigninRisk"
            EntityKey = "signInRiskLevels"
        })           
    }
    
    if($obj.conditions.platforms.includePlatforms.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.platforms.includePlatforms))
        {
            if($id -eq "all")
            {
                $tmpObjs += Get-LanguageString "AzureIAM.allDevicePlatforms"
            }
            else
            {
                $tmpObjs += Get-LanguageString "AzureIAM.$($id)DisplayName"
            }
        }        

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value =  $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = Get-LanguageString "AzureIAM.devicePlatform"
            EntityKey = "includePlatforms"
        })           
    }
    
    if($obj.conditions.platforms.excludePlatforms.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.platforms.excludePlatforms))
        {
            $tmpObjs += Get-LanguageString "AzureIAM.$($id)DisplayName"
        }        

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $excludeLabel
            Value =  $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = Get-LanguageString "AzureIAM.devicePlatform"
            EntityKey = "excludePlatforms"
        })           
    }
    
    if(-not $script:allNamedLocations -and ($obj.conditions.locations.includeLocations.Count -gt 0 -or $obj.conditions.locations.excludeLocations.Count))
    {
        # Might be better to get them one by one
        $script:allNamedLocations = (Invoke-GraphRequest -url "/identity/conditionalAccess/namedLocations?`$select=displayName,Id&top=999" -ODataMetadata "minimal").value
        if(-not $script:allNamedLocations) {  $script:allNamedLocations = @()}
        elseif($script:allNamedLocations -isnot [Object[]]) {  $script:allNamedLocations = @($script:allNamedLocations) }

        $script:allNamedLocations += [PSCustomObject]@{
            displayName = Get-LanguageString "AzureIAM.chooseLocationTrustedIpsItem"
            id =  "00000000-0000-0000-0000-000000000000"
        }
    }

    if($obj.conditions.locations.includeLocations.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.locations.includeLocations))
        {
            if($id -eq "AllTrusted")
            {
                $tmpObjs += Get-LanguageString "AzureIAM.allTrustedLocationLabel"
            }
            elseif($id -eq "All")
            {
                $tmpObjs += Get-LanguageString "AzureIAM.locationsAllLocationsLabel"
            }
            else
            {
                $idObj = $script:allNamedLocations | Where Id -eq $id
                $tmpObjs += ?? $idObj.displayName $id
            }
        }        

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value =  $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = Get-LanguageString "AzureIAM.policyConditionLocation"
            EntityKey = "includeLocations"
        })           
    }
    
    if($obj.conditions.locations.excludeLocations.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.locations.excludeLocations))
        {
            if($id -eq "AllTrusted")
            {
                $tmpObjs += Get-LanguageString "AzureIAM.allTrustedLocationLabel"
            }
            elseif($id -eq "All")
            {
                $tmpObjs += Get-LanguageString "AzureIAM.locationsAllLocationsLabel"
            }
            else
            {
                $idObj = $script:allNamedLocations | Where Id -eq $id
                $tmpObjs += ?? $idObj.displayName $id
            }
        }        

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $excludeLabel
            Value =  $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = Get-LanguageString "AzureIAM.policyConditionLocation"
            EntityKey = "excludeLocations"
        })           
    }
    
    if($obj.conditions.clientAppTypes.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.clientAppTypes))
        {
            if($id -eq "browser") { $tmpObjs += Get-LanguageString "AzureIAM.clientAppWebBrowser" }
            elseif($id -eq "mobileAppsAndDesktopClients") { $tmpObjs += Get-LanguageString "AzureIAM.clientAppMobileDesktop" }
            elseif($id -eq "exchangeActiveSync") { $tmpObjs += Get-LanguageString "AzureIAM.clientAppExchangeActiveSync" }
            elseif($id -eq "other") { $tmpObjs += Get-LanguageString "AzureIAM.clientTypeOtherClients" }
            elseif($id -eq "all") { break } # Not configured
            else
            {
                $tmpObjs += $id
                Write-Log "Unsupported app type: $id" 3
            }
        }        

        if($tmpObjs.Count -gt 0)
        {
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = $includeLabel
                Value =  $tmpObjs -join $script:objectSeparator
                Category = $category
                SubCategory = Get-LanguageString "AzureIAM.policyConditioniClientApp"
                EntityKey = "clientAppTypes"
            })
        }           
    }

    if($obj.conditions.devices.includeDevices.Count -gt 0)
    {
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $includeLabel
            Value =  Get-LanguageString "AzureIAM.deviceStateAll"
            Category = $category
            SubCategory = Get-LanguageString "AzureIAM.deviceStateConditionSelectorLabel"
            EntityKey = "includeDevices"
        })           
    }

    if($obj.conditions.devices.excludeDevices.Count -gt 0)
    {
        $tmpObjs = @() 
        foreach($id in ($obj.conditions.devices.excludeDevices))
        {
            $tmpObjs += Get-LanguageString "AzureIAM.classicPolicyControlRequire$($id)Device"
        }        

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $excludeLabel
            Value =  $tmpObjs -join $script:objectSeparator
            Category = $category
            SubCategory = Get-LanguageString "AzureIAM.deviceStateConditionSelectorLabel"
            EntityKey = "excludeDevices"
        })           
    }
    
    ###################################################
    # Grant
    ###################################################

    $category = Get-LanguageString "AzureIAM.policyControlBladeTitle"

    Add-CustomSettingObject ([PSCustomObject]@{
        Name = Get-LanguageString "AzureIAM.policyControlContentDescription"
        Value =  Get-LanguageString "AzureIAM.$((?: (($obj.grantControls.builtInControls | Where { $_ -eq "block"}) -ne $null) "policyControlBlockAccessDisplayedName" "policyControlAllowAccessDisplayedName"))"
        Category = $category
        SubCategory = ""
        EntityKey = "policyControl"
    })

    if(($obj.grantControls.builtInControls | Where { $_ -eq "block"}))
    {
        if(($obj.grantControls.builtInControls | Where { $_ -eq "mfa"}))
        {
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = Get-LanguageString "AzureIAM.policyControlMfaChallengeDisplayedName"
                Value =   Get-LanguageString "Inputs.enabled"
                Category = $category
                SubCategory = ""
                EntityKey = "mfa"
            })
        }

        if(($obj.grantControls.builtInControls | Where { $_ -eq "compliantDevice"}))
        {
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = Get-LanguageString "AzureIAM.policyControlCompliantDeviceDisplayedName"
                Value =   Get-LanguageString "Inputs.enabled"
                Category = $category
                SubCategory = ""
                EntityKey = "compliantDevice"
            })
        }

        if(($obj.grantControls.builtInControls | Where { $_ -eq "domainJoinedDevice"}))
        {
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = Get-LanguageString "AzureIAM.policyControlRequireDomainJoinedDisplayedName"
                Value =   Get-LanguageString "Inputs.enabled"
                Category = $category
                SubCategory = ""
                EntityKey = "domainJoinedDevice"
            })
        }
        
        if(($obj.grantControls.builtInControls | Where { $_ -eq "approvedApplication"}))
        {
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = Get-LanguageString "AzureIAM.policyControlRequireMamDisplayedName"
                Value =   Get-LanguageString "Inputs.enabled"
                Category = $category
                SubCategory = ""
                EntityKey = "approvedApplication"
            })
        }
        
        if(($obj.grantControls.builtInControls | Where { $_ -eq "compliantApplication"}))
        {
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = Get-LanguageString "AzureIAM.policyControlRequireCompliantAppDisplayedName"
                Value =   Get-LanguageString "Inputs.enabled"
                Category = $category
                SubCategory = ""
                EntityKey = "compliantApplication"
            })
        }

        if(($obj.grantControls.builtInControls | Where { $_ -eq "passwordChange"}))
        {
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = Get-LanguageString "AzureIAM.policyControlRequiredPasswordChangeDisplayedName"
                Value =   Get-LanguageString "Inputs.enabled"
                Category = $category
                SubCategory = ""
                EntityKey = "passwordChange"
            })
        }
        
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = Get-LanguageString "AzureIAM.descriptionContentForControlsAndOr"
            Value =   Get-LanguageString "AzureIAM.$((?: ($obj.grantControls.operator -eq "OR") "requireOneControlText" "requireAllControlsText"))" 
            Category = $category
            SubCategory = ""
            EntityKey = "grantOperator"
        })
}

    ###################################################
    # Session
    ###################################################

    $category = Get-LanguageString "AzureIAM.sessionControlBladeTitle"

    if($obj.sessionControls.applicationEnforcedRestrictions.isEnabled -eq $true)
    {
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = Get-LanguageString "AzureIAM.sessionControlsAppEnforcedLabel"
            Value = Get-LanguageString "Inputs.enabled"
            Category = $category
            SubCategory = ""
            EntityKey = "applicationEnforcedRestrictions"
        })
    }
    
    if($obj.sessionControls.cloudAppSecurity.isEnabled -eq $true)
    {
        if($obj.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "mcasConfigured") { $strId = "useCustomControls" }
        elseif($obj.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "monitorOnly") { $strId = "monitorOnly" }
        elseif($obj.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "blockDownloads") { $strId = "blockDownloads" }

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = Get-LanguageString "AzureIAM.sessionControlsCasLabel"
            Value =  Get-LanguageString "AzureIAM.CAS.BuiltinPolicy.Option.$strId"
            Category = $category
            SubCategory = ""
            EntityKey = "cloudAppSecurity"
        })
    }
    
    if($obj.sessionControls.signInFrequency.isEnabled -eq $true)
    {
        if($obj.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "mcasConfigured") { $strId = "useCustomControls" }
        elseif($obj.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "monitorOnly") { $strId = "monitorOnly" }
        elseif($obj.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "blockDownloads") { $strId = "blockDownloads" }

        if($obj.sessionControls.signInFrequency.type -eq "hours")
        {
            if($obj.sessionControls.signInFrequency.value -gt 1)
            {
                $value = (Get-LanguageString "AzureIAM.SessionLifetime.SignInFrequency.Option.Hour.plural") -f $obj.sessionControls.signInFrequency.value
            }
            else
            {
                $value = Get-LanguageString "AzureIAM.SessionLifetime.SignInFrequency.Option.Hour.singular"
            }
        }
        else
        {
            if($obj.sessionControls.signInFrequency.value -gt 1)
            {
                $value = (Get-LanguageString "AzureIAM.SessionLifetime.SignInFrequency.Option.Day.plural") -f $obj.sessionControls.signInFrequency.value
            }
            else
            {
                $value = Get-LanguageString "AzureIAM.SessionLifetime.SignInFrequency.Option.Day.singular"
            }
        }

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = Get-LanguageString "AzureIAM.SessionLifetime.SignInFrequency.Option.label"
            Value =  $value
            Category = $category
            SubCategory = ""
            EntityKey = "SignInFrequency"
        })
    }
    
    if($obj.sessionControls.persistentBrowser.isEnabled -eq $true)
    {
        Add-CustomSettingObject ([PSCustomObject]@{
            Name = Get-LanguageString "AzureIAM.SessionLifetime.PersistentBrowser.Option.label"
            Value =  Get-LanguageString "AzureIAM.SessionLifetime.PersistentBrowser.Option.$($obj.sessionControls.persistentBrowser.mode)"
            Category = $category
            SubCategory = ""
            EntityKey = "persistentBrowser"
        })
    }    
}

#region Document Policy Sets
function Invoke-CDDocumentPolicySet
{
    param($documentationObj)

    $obj = $documentationObj.Object
    $objectType = $documentationObj.ObjectType

    $script:objectSeparator = ?? $global:cbDocumentationObjectSeparator.SelectedValue ([System.Environment]::NewLine)
    $script:propertySeparator = ?? $global:cbDocumentationPropertySeparator.SelectedValue ","
    
    ###################################################
    # Basic info
    ###################################################

    Add-BasicDefaultValues $obj $objectType
    Add-BasicPropertyValue (Get-LanguageString "TableHeaders.configurationType") (Get-LanguageString "SettingDetails.appConfiguration")
    

    ###################################################
    # Settings
    ###################################################

    $addedSettings = @()

    $policySetSettings = (
        [PSCustomObject]@{
            Types = @(
                @('#microsoft.graph.mobileAppPolicySetItem','appTitle'),
                @('#microsoft.graph.targetedManagedAppConfigurationPolicySetItem','appConfigurationTitle'),
                @('#microsoft.graph.managedAppProtectionPolicySetItem','appProtectionTitle'),
                @('#microsoft.graph.iosLobAppProvisioningConfigurationPolicySetItem','iOSAppProvisioningTitle'))
            Category = (Get-LanguageString "PolicySet.appManagement")
        },
        [PSCustomObject]@{
            Types = @(
                @('#microsoft.graph.deviceConfigurationPolicySetItem','deviceConfigurationTitle'),
                @('#microsoft.graph.deviceCompliancePolicyPolicySetItem','deviceComplianceTitle'),
                @('#microsoft.graph.deviceManagementScriptPolicySetItem','powershellScriptTitle'))
            Category = (Get-LanguageString "PolicySet.deviceManagement")
        }, 
        [PSCustomObject]@{
            Types = @(
                @('#microsoft.graph.enrollmentRestrictionsConfigurationPolicySetItem','deviceTypeRestrictionTitle'),
                @('#microsoft.graph.windowsAutopilotDeploymentProfilePolicySetItem','windowsAutopilotDeploymentProfileTitle'),
                @('#microsoft.graph.windows10EnrollmentCompletionPageConfigurationPolicySetItem','enrollmentStatusSettingTitle'))
            Category = (Get-LanguageString "PolicySet.deviceEnrollment")
        }
    )

    foreach($policySettingType in $policySetSettings)
    {
        foreach($subType in $policySettingType.Types)
        {
            foreach($setting in ($obj.items | where '@OData.Type' -eq $subType[0]))
            {
                if($setting.status -eq "error")
                {
                    Write-Log "Skipping missing $($subType[0]) type with id $($setting.id). Error code: $($setting.errorCode)"
                    continue
                }

                Add-CustomSettingObject ([PSCustomObject]@{
                    Name = $setting.displayName
                    Value = (Get-CDDocumentPolicySetValue $setting)
                    EntityKey = $setting.id
                    Category = $policySettingType.Category
                    SubCategory = (Get-LanguageString "PolicySet.$($subType[1])")
                })
            }
        }
    }
}

function Get-CDDocumentPolicySetValue
{
    param($policySetItem)

    if($policySetItem.'@OData.Type' -eq '#microsoft.graph.enrollmentRestrictionsConfigurationPolicySetItem' -or 
        $policySetItem.'@OData.Type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfigurationPolicySetItem')
    {
        return $policySetItem.Priority
    }
    elseif($policySetItem.'@OData.Type' -eq '#microsoft.graph.windowsAutopilotDeploymentProfilePolicySetItem')
    {
        if($policySetItem.itemType -eq '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile')
        {
            return (Get-LanguageString "Autopilot.DirectoryService.azureAD")
        }
        elseif($policySetItem.itemType -eq '#microsoft.graph.activeDirectoryWindowsAutopilotDeploymentProfile')
        {
            return (Get-LanguageString "Autopilot.DirectoryService.activeDirectoryAD")
        }
    }
    # ToDo: Add support for all PolicySet items 
}
#endregion

#region Custom Profile
function Invoke-CDDocumentCustomOMAUri
{
    param($documentationObj)

    $obj = $documentationObj.Object
    $objectType = $documentationObj.ObjectType

    $script:objectSeparator = ?? $global:cbDocumentationObjectSeparator.SelectedValue ([System.Environment]::NewLine)
    $script:propertySeparator = ?? $global:cbDocumentationPropertySeparator.SelectedValue ","
    
    ###################################################
    # Basic info
    ###################################################

    Add-BasicDefaultValues $obj $objectType
    #Add-BasicPropertyValue (Get-LanguageString "TableHeaders.configurationType") (Get-LanguageString "PolicyType.custom")

    $platformId = Get-ObjectPlatformFromType $obj
    Add-BasicPropertyValue (Get-LanguageString "Inputs.platformLabel") (Get-LanguageString "Platform.$platformId")

    ###################################################
    # Settings
    ###################################################

    $addedSettings = @()
    $category = Get-LanguageString "SettingDetails.customPolicyOMAURISettingsName"

    foreach($setting in $obj.omaSettings)
    {
        # Add the name of the OMA-URI setting
        Add-CustomSettingObject ([PSCustomObject]@{            
            Name = (Get-LanguageString "SettingDetails.nameName")
            Value =  $setting.displayName
            EntityKey = "displayName_$($setting.omaUri)"
            Category = $category
            SubCategory = $setting.displayName
        })

        # Add the description of the OMA-URI setting
        Add-CustomSettingObject ([PSCustomObject]@{            
            Name = (Get-LanguageString "TableHeaders.description")
            Value =  $setting.description
            EntityKey = "description_$($setting.omaUri)"
            Category = $category
            SubCategory = $setting.displayName
        })

        # Add the OMA-URI path of the OMA-URI setting
        Add-CustomSettingObject ([PSCustomObject]@{            
            Name = (Get-LanguageString "SettingDetails.oMAURIName")
            Value =  $setting.omaUri
            EntityKey = "omaUri_$($setting.omaUri)"
            Category = $category
            SubCategory = $setting.displayName
        })

        if($setting.'@OData.Type' -eq '#microsoft.graph.omaSettingString')
        {
            $value = (Get-LanguageString "SettingDetails.stringName")
        }
        elseif($setting.'@OData.Type' -eq '#microsoft.graph.omaSettingBase64')
        {
            $value = (Get-LanguageString "SettingDetails.base64Name")
        }
        elseif($setting.'@OData.Type' -eq '#microsoft.graph.omaSettingBoolean')
        {
            $value = (Get-LanguageString "SettingDetails.booleanName")
        }
        elseif($setting.'@OData.Type' -eq '#microsoft.graph.omaSettingDateTime')
        {
            $value = (Get-LanguageString "SettingDetails.dateTimeName")
        }
        elseif($setting.'@OData.Type' -eq '#microsoft.graph.omaSettingFloatingPoint')
        {
            $value = (Get-LanguageString "SettingDetails.floatingPointName")
        }
        elseif($setting.'@OData.Type' -eq '#microsoft.graph.omaSettingInteger')
        {
            $value = (Get-LanguageString "SettingDetails.integerName")
        }
        elseif($setting.'@OData.Type' -eq '#microsoft.graph.omaSettingStringXml')
        {
            $value = (Get-LanguageString "SettingDetails.stringXMLName")
        }
        else
        {
            $value = $null
        }

        if($value)
        {
            # Add the type of the OMA-URI setting
            Add-CustomSettingObject ([PSCustomObject]@{
                Name = (Get-LanguageString "SettingDetails.dataTypeName")
                Value =  $value
                EntityKey = "type_$($setting.omaUri)"
                Category = $category
                SubCategory = $setting.displayName
            })
        }

        $value = $setting.value
        # Add the type of the OMA-URI setting
        if($setting.isEncrypted -ne $true)
        {
            if($setting.'@OData.Type' -eq '#microsoft.graph.omaSettingStringXml')
            {
                $value = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($value))
            }

            Add-CustomSettingObject ([PSCustomObject]@{
                Name = (Get-LanguageString "SettingDetails.valueName")
                Value =  $value
                EntityKey = "value_$($setting.omaUri)"
                Category = $category
                SubCategory = $setting.displayName
            })
        }
        else # ToDo: Add check button
        {
            if($obj.'@ObjectFromFile' -ne $true)
            {
                $xmlValue = Invoke-GraphRequest -Url "/deviceManagement/deviceConfigurations/$($obj.Id)/getOmaSettingPlainTextValue(secretReferenceValueId='$($setting.secretReferenceValueId)')"
                $value = $xmlValue.Value
                if($value)
                {
                    Add-CustomSettingObject ([PSCustomObject]@{
                        Name = (Get-LanguageString "SettingDetails.valueName")
                        Value =  $value
                        EntityKey = "value_$($setting.omaUri)"
                        Category = $category
                        SubCategory = $setting.displayName
                    })
                }
            }
        }        
    }
}
#endregion

#region Notification
function Invoke-CDDocumentNotification
{
    param($documentationObj)

    $obj = $documentationObj.Object
    $objectType = $documentationObj.ObjectType

    $script:objectSeparator = ?? $global:cbDocumentationObjectSeparator.SelectedValue ([System.Environment]::NewLine)
    $script:propertySeparator = ?? $global:cbDocumentationPropertySeparator.SelectedValue ","
    
    ###################################################
    # Basic info
    ###################################################

    Add-BasicDefaultValues $obj $objectType
    
    Add-BasicPropertyValue (Get-LanguageString "TableHeaders.configurationType") (Get-LanguageString "Titles.notifications")

    ###################################################
    # Settings
    ###################################################

    $category = Get-LanguageString "TableHeaders.settings"

    if($obj.brandingOptions)
    {
        $brandingOptions = $obj.brandingOptions.Split(',')
    }
    else
    {
        $brandingOptions = @()
    }

    foreach($brandingOption in @('includeCompanyLogo','includeCompanyName','includeContactInformation','includeCompanyPortalLink'))
    {
        if($brandingOption -eq 'includeCompanyLogo')
        {
            $label = (Get-LanguageString "NotificationMessage.companyLogo")
        }
        elseif($brandingOption -eq 'includeCompanyName')
        {
            $label = (Get-LanguageString "NotificationMessage.companyName")
        }
        elseif($brandingOption -eq 'includeContactInformation')
        {
            $label = (Get-LanguageString "NotificationMessage.companyContact")
        }
        elseif($brandingOption -eq 'includeCompanyPortalLink')
        {
            $label = (Get-LanguageString "NotificationMessage.iwLink")
        }

        if(($brandingOption -in $brandingOptions))
        {
            $value = Get-LanguageString "BooleanActions.enable"
        }
        else
        {
            $value = Get-LanguageString "BooleanActions.disable"
        }

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $label
            Value =  $value
            EntityKey = $brandingOption
            Category = $category
            SubCategory = $null
        })
    }
    
    #$subCategory = Get-LanguageString "NotificationMessage.localeLabel"
    $subCategory = Get-LanguageString "NotificationMessage.listTitle"

    foreach($template in $obj.localizedNotificationMessages)
    {
        $first,$second = $template.locale.Split('-')
        $baseInfo = [cultureinfo]$first
        $lng = $baseInfo.EnglishName.ToLower()
        if($first -eq 'en')
        {
            if($second -eq "US")
            {
                $lng = ($lng + "US")
            }
            elseif($second -eq "GB")
            {
                $lng = ($lng + "UK")
            }
        }
        elseif($first -eq 'es')
        {
            if($second -eq "es")
            {
                $lng = ($lng + "Spain")
            }
            elseif($second -eq "mx")
            {
                $lng = ($lng + "Mexico")
            }
        }
        elseif($first -eq 'fr')
        {
            if($second -eq "ca")
            {
                $lng = ($lng + "Canada")
            }
            elseif($second -eq "fr")
            {
                $lng = ($lng + "France")
            }
        }
        elseif($first -eq 'pt')
        {
            if($second -eq "pt")
            {
                $lng = ($lng + "Portugal")
            }
            elseif($second -eq "br")
            {
                $lng = ($lng + "Brazil")
            }
        }
        elseif($first -eq 'zh')
        {
            if($second -eq "tw")
            {
                $lng = ($lng + "Traditional")
            }
            elseif($second -eq "cn")
            {
                $lng = ($lng + "Simplified")
            }
        }
        elseif($first -eq 'nb')
        {
            $lng = "norwegian"
        }        
       
        $label = Get-LanguageString "NotificationMessage.NotificationMessageTemplatesTab.$lng"

        if(-not $label) { continue }

        $value = $template.subject

        if($template.isDefault)
        {
            $value = ($value + $script:objectSeparator + (Get-LanguageString "NotificationMessage.isDefaultLocale") + ": " + (Get-LanguageString "SettingDetails.trueOption"))
        }

        $fullValue = ($value + $script:objectSeparator + $template.messageTemplate)

        Add-CustomSettingObject ([PSCustomObject]@{
            Name = $label
            Value =  $fullValue            
            EntityKey = $template.locale
            Category = $category
            SubCategory = $subCategory
        })        
    }
}
#endregion