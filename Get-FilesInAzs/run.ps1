# Input bindings are passed in via param block.
param($Timer)

$ErrorActionPreference = "stop"

function invoke-GitHubApiRequest {
    param (
        $apiEndpoint
    )
    $githubToken = $env:GithubToken
    $header = @{
        "Authorization" = "token " + $githubToken
    }
    return Invoke-RestMethod -Method GET -Uri $apiEndpoint -Headers $header
}

$baseUrl = "https://api.github.com/repos/"
$repository = "MicrosoftDocs/azure-stack-docs"
$apiPath = "/commits"
$apiEndpoint = $baseUrl + $repository + $apiPath

# Get the latest sha
$Commits = invoke-GitHubApiRequest $apiEndpoint
$latestSha = $Commits[0].sha

# Get trees in the latest sha
$apiPath = "/git/trees/" + $latestSha
$apiEndpoint = $baseUrl + $repository + $apiPath
$res = invoke-GitHubApiRequest $apiEndpoint
$articlesSha = $res.tree.where({ $_.path -eq "azure-stack"}).sha

# Get trees in the articles
$apiPath = "/git/trees/" + $articlesSha
$apiEndpoint = $baseUrl + $repository + $apiPath
$res = invoke-GitHubApiRequest $apiEndpoint
$targetTrees = $res.tree.where({ $_.type -eq "tree"})

$document = @{}
$document.sha = $latestSha
$files = New-Object System.Collections.ArrayList

foreach ($targetTree in $targetTrees) {
    $apiPath = "/git/trees/" + $targetTree.sha + "?recursive=1" 
    $apiEndpoint = $baseUrl + $repository + $apiPath
    $res = invoke-GitHubApiRequest $apiEndpoint
    $filesInTree = $res.tree.Where({ $_.path -match ".md$"}) | Select-Object path, sha

    foreach ($fileInTree in $filesInTree) {
        $tmp = @{}
        $tmp.path = "azure-stack/" + $targetTree.path + "/" + $fileInTree.path
        $tmp.sha = $fileInTree.sha
        $files.add($tmp) | Out-Null           
    }
}
$document.files = $files

$date = Get-date -Format yyyyMMdd
$document = @{
    "sha" = $latestSha 
    "files" = $files
} | ConvertTo-Json -depth 10
Out-File -Encoding Ascii -FilePath "d:\local\azs-$date.json" -Force -inputObject $document

Write-Output "Updating the new file to storage account."
$storageAccount =Get-AzStorageAccount -Name docchangefeed -ResourceGroupName docChangeFeed
Set-AzStorageBlobContent -File "d:\local\azs-$date.json" `
  -Container '$web' `
  -Blob "azurestack\$date.json" `
  -Context $storageAccount.Context -Force