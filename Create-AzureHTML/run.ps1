# Input bindings are passed in via param block.
param($Timer)

$ErrorActionPreference = "stop"

function ConvertTo-Base64 {
    param (
        $string
    )
    $byte = ([System.Text.Encoding]::Default).GetBytes($string)
    return [Convert]::ToBase64String($byte)
}

function Convert-md5hash {
    param (
        $string
    )
    $sha256 = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding
    $hash = [System.BitConverter]::ToString($sha256.ComputeHash($utf8.GetBytes($string)))
    $hash = $hash -replace "-",""
    return $hash.ToLower()
}

$helpers = @{
    ConvertFromGitToDocs = { 
        param($gitPath)
        $gitPath -match "(.*?/)" | Out-Null
        $tmpGitPath = $gitPath -replace "$($Matches[1])","https://docs.microsoft.com/en-us/azure/"  
        return $tmpGitPath -replace ".md$",""  
    }
}

$template = @'
---
title: Azure Update at <%= $date %>
date: <%= $date %>
draft: false
tags: [
]
---

<% $categories | each { -%>
<% $category = $_ -%>
<% $updates = $updateinfo.where({ $_.path -like "*/$category/*" }) -%>
### <%= $category %>
<% $updates | each { -%>
- [<%= $_.path %>](<%= $_.compareUrl %>) ([To docs](<%= ConvertFromGitToDocs $_.path %>?WT.mc_id=AZ-MVP-5003408))
<% } -%>    
<% } -%>
'@

$storageAccount =Get-AzStorageAccount -Name docchangefeed -ResourceGroupName docChangeFeed
$latestTwo = Get-AzStorageBlob -Container '$web' -Context $storageAccount.Context -Prefix "azure/" | Sort-Object LastModified -Descending -Top 2

$fqdn = "https://docchangefeed.z11.web.core.windows.net/"
$url = $fqdn + $latestTwo[0].Name 
$latestList = Invoke-RestMethod -Uri $url 
$url = $fqdn + $latestTwo[1].Name 
$previousList = Invoke-RestMethod -Uri $url 

Write-output "Comparing $($latestTwo[0].Name) and $($latestTwo[1].Name)."

$baseUrl = "https://github.com/"
$repository = "MicrosoftDocs/azure-docs"
$apiPath = "/compare/"
$apiEndpoint = $baseUrl + $repository + $apiPath + $previousList.sha.Substring(0,7) + ".." + $latestList.sha.Substring(0,7) 

$UpdateInfo = New-Object System.Collections.ArrayList
if ($latestList.sha -ne $previousList.sha){
    foreach ($latestFile in $latestList.files) {
        
        foreach ($previousFile in $previousList.files) {
            if ( $previousfile.path -eq $latestFile.Path ){
                $oldFile = $previousFile              
            }
        }
        
        $tmp = @{}
        if ( $latestFile.sha -ne $oldFile.sha ){
            Write-Output "$($latestFile.path) was updated"
            $hash = Convert-md5hash $latestFile.path
            $compareUrl = $apiEndpoint + "#diff-" + $hash
            $tmp.path = $latestFile.path
            $tmp.compareUrl = $compareUrl
            $UpdateInfo.add($tmp) | Out-Null        
        }
    }

    $UpdateInfo = $UpdateInfo | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $date = Get-date -Format yyyy-MM-dd

    $Categories = New-Object System.Collections.ArrayList
    $category = ""
    $updateinfo.path | ForEach-Object {
        $_ -match "articles/(.*?)/" | Out-Null
        $category = $Matches[1]
        $Categories.Add($category) | Out-Null
    }
    $categories = $categories | Sort-Object -Unique

    $html = Invoke-EpsTemplate -Template $template -helpers $helpers -Safe -binding @{
        date = $date
        updateInfo = $UpdateInfo
        categories = $categories
    }

    $base64Html = ConvertTo-Base64 $html

    $baseUrl = "https://api.github.com/repos/"
    $repository = "kongou-ae/azdocChangefeed"
    $apiPath = "/contents/content/posts/azure-update-$date.md"
    $apiEndpoint = $baseUrl + $repository + $apiPath

    $githubToken = $env:GithubToken
    $header = @{
        "Authorization" = "token " + $githubToken
    }

    $body = @{
        "message" = "update"
        "content" = $base64Html
    } | ConvertTo-Json -Compress

    Invoke-RestMethod -Method PUT -Headers $header -Body $body -Uri $apiEndpoint

}

