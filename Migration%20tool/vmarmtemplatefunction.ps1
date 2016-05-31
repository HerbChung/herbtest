$SubscriptionName = "CAT Solution Accelerator WW"
Login-AzureRmAccount -SubscriptionName $SubscriptionName

Function Modify-VMARMTemplate {

    param
    (
       [parameter(Mandatory=$true)]
       [String]
       $SourceResourceGroupName, 
      
       [parameter(Mandatory=$true)]
       [String]
       $TargetLocation,       
 
       [parameter(Mandatory=$true)]
       [String]
       $TargetResourceGroup, 
      
       [parameter(Mandatory=$false)]
       [String]
       $TargetStorageAccount    

    )
    #Get the Target Resource Group ARM Template
    $Sourcetemplatefolder = New-Item -ItemType directory -Path "$Env:TEMP\$SourceResourceGroupName" -Force
    $Sourcetemplatepath = $Env:TEMP + "\" + $SourceResourceGroupName + "\" + $SourceResourceGroupName + ".json"
    Export-AzureRmResourceGroup -ResourceGroupName $SourceResourceGroupName -Path $Sourcetemplatepath -IncludeParameterDefaultValue -Force
    
    #Import the source template into array
    $sourcetemplate = Get-Content -raw -Path $Sourcetemplatepath | ConvertFrom-Json

  
    #Set Target ARM Template with source settings
    $targettemplate = New-Object PSObject
    $targettemplate | Add-Member -Name '$schema' -MemberType NoteProperty -Value $sourcetemplate.'$schema'
    $targettemplate | Add-Member -Name "contentVersion" -MemberType Noteproperty -Value $sourcetemplate.contentVersion
    $targettemplate | Add-Member -Name "parameters" -MemberType Noteproperty -Value $sourcetemplate.parameters
    $targettemplate | Add-Member -Name "variables" -MemberType Noteproperty -Value $sourcetemplate.variables
    $targettemplate | Add-Member -Name "resources" -MemberType Noteproperty -Value $null

    #Select related Resource       
    $targetresources = @()
    
    $computesourcetemplate = $sourcetemplate.resources | Where-Object { ($_.type -eq "Microsoft.Compute/virtualMachines") }
    Foreach ($c in $computesourcetemplate){
    
    $crspropstorprofile = New-Object PSObject
    $crspropstorprofile | Add-Member -Name "osDisk" -MemberType NoteProperty -Value $c.properties.storageProfile.osdisk
    $crspropstorprofile | Add-Member -Name "dataDisks" -MemberType NoteProperty -Value $c.properties.storageProfile.dataDisks
    $crspropstorprofile.osdisk.createOption = "Attach"

    if ($c.properties.storageProfile.imageReference.publisher -eq "MicrosoftWindowsServer") {
    $ostype = "Windows"
    }
    else {
    $ostype = "Linux"
    }
    $crspropstorprofile.osdisk | Add-Member -Name "osType" -MemberType NoteProperty -Value $ostype -Force

    $osurl = $c.properties.storageProfile.osDisk.vhd.uri.Replace(".blob.core.windows.net", ".blob.core.chinacloudapi.cn")
    $crspropstorprofile.osdisk.vhd.uri = $osurl
    

    $crsprop = New-Object PSObject
    $crsprop | Add-Member -Name "hardwareProfile" -MemberType NoteProperty -Value $c.properties.hardwareProfile
    $crsprop | Add-Member -Name "storageProfile" -MemberType NoteProperty -Value $crspropstorprofile
    $crsprop | Add-Member -Name "networkProfile" -MemberType NoteProperty -Value $c.properties.networkProfile


    $crs = New-Object PSObject
    $crs | Add-Member -Name "type" -MemberType NoteProperty -Value $c.type
    $crs | Add-Member -Name "name" -MemberType NoteProperty -Value $c.name
    $crs | Add-Member -Name "apiVersion" -MemberType NoteProperty -Value $c.apiVersion
    $crs | Add-Member -Name "location" -MemberType NoteProperty -Value $TargetLocation
    $crs | Add-Member -Name "tags" -MemberType NoteProperty -Value $c.tags
    $crs | Add-Member -Name "properties" -MemberType NoteProperty -Value $crsprop
    $crs | Add-Member -Name "dependsOn" -MemberType NoteProperty -Value $c.dependsOn

    $targetresources += $crs
    }

    $nssourcetemplate = $sourcetemplate.resources | Where-Object { ($_.type -match "Microsoft.Network*") -or ($_.type -match "Microsoft.Storage*") } 
    Foreach($ns in $nssourcetemplate) {
    
    $ns.location = $TargetLocation

    $targetresources += $ns
    }


    $targettemplate.resources = $targetresources 

    $targetjson = $targettemplate | ConvertTo-Json -Depth 7
    $targettemplatepath = $Env:TEMP + "\" + $SourceResourceGroupName + "\" + $SourceResourceGroupName + "target.json"
    $targetjson -replace "\\u0027", "'" | Out-File $targettemplatepath

}