[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FilePath,

  [string]$Key1 = $env:UDROP_KEY1,
  [string]$Key2 = $env:UDROP_KEY2,
  [string]$FolderId = $env:UDROP_FOLDER_ID,
  [ValidateSet("PowerShell", "Curl")]
  [string]$ApiMode = "PowerShell",
  [ValidateSet("Workflow", "Curl")]
  [string]$UploadMode = "Workflow",
  [int]$TimeoutSec = 60,
  [switch]$ForceUpload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-UdropAuth {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AuthKey1,
    [Parameter(Mandatory = $true)]
    [string]$AuthKey2
  )

  $raw = $null
  try {
    $raw = (Invoke-WebRequest -Uri "https://www.udrop.com/api/v2/authorize" -Method Post -TimeoutSec $TimeoutSec -Body @{
      key1 = $AuthKey1
      key2 = $AuthKey2
    } -UseBasicParsing).Content
  } catch {
    throw "uDrop auth request failed: $($_.Exception.Message)"
  }

  if (-not $raw) {
    throw "uDrop auth returned an empty response."
  }

  try {
    $json = $raw | ConvertFrom-Json
  } catch {
    throw "uDrop auth returned non-JSON: $raw"
  }

  $token = @(
    $json.access_token,
    $json.token,
    $json.data.access_token,
    $json.data.token,
    $json.response.access_token,
    $json.response.token
  ) | Where-Object { $_ } | Select-Object -First 1

  $accountId = @(
    $json.account_id,
    $json.acc_id,
    $json.user_id,
    $json.data.account_id,
    $json.data.acc_id,
    $json.data.user_id,
    $json.response.account_id,
    $json.response.acc_id,
    $json.response.user_id
  ) | Where-Object { $_ } | Select-Object -First 1

  if ($token) { $token = "$token".Trim() }
  if ($accountId) { $accountId = "$accountId".Trim() }

  if ($json._status -ne "success" -or -not $token -or -not $accountId) {
    $authJson = $json | ConvertTo-Json -Depth 10 -Compress
    throw "uDrop auth did not succeed: $authJson"
  }

  return @{
    token = $token
    account_id = $accountId
  }
}

function Get-UdropAuthCurl {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AuthKey1,
    [Parameter(Mandatory = $true)]
    [string]$AuthKey2
  )

  $curlArgs = @(
    "--silent",
    "--show-error",
    "--max-time", "$TimeoutSec",
    "--request", "POST",
    "--data", "key1=$AuthKey1",
    "--data", "key2=$AuthKey2",
    "https://www.udrop.com/api/v2/authorize"
  )

  try {
    $raw = & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
      throw "curl authorize failed with exit code $LASTEXITCODE."
    }
  } catch {
    throw "uDrop curl auth request failed: $($_.Exception.Message)"
  }

  if (-not $raw) {
    throw "uDrop curl auth returned an empty response."
  }

  try {
    $json = $raw | ConvertFrom-Json
  } catch {
    throw "uDrop curl auth returned non-JSON: $raw"
  }

  $token = @(
    $json.access_token,
    $json.token,
    $json.data.access_token,
    $json.data.token,
    $json.response.access_token,
    $json.response.token
  ) | Where-Object { $_ } | Select-Object -First 1

  $accountId = @(
    $json.account_id,
    $json.acc_id,
    $json.user_id,
    $json.data.account_id,
    $json.data.acc_id,
    $json.data.user_id,
    $json.response.account_id,
    $json.response.acc_id,
    $json.response.user_id
  ) | Where-Object { $_ } | Select-Object -First 1

  if ($token) { $token = "$token".Trim() }
  if ($accountId) { $accountId = "$accountId".Trim() }

  if ($json._status -ne "success" -or -not $token -or -not $accountId) {
    $authJson = $json | ConvertTo-Json -Depth 10 -Compress
    throw "uDrop curl auth did not succeed: $authJson"
  }

  return @{
    token = $token
    account_id = $accountId
  }
}

function Invoke-UdropListingCurl {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Token,
    [Parameter(Mandatory = $true)]
    [string]$AccountId,
    [string]$ParentFolderId
  )

  $curlArgs = @(
    "--silent",
    "--show-error",
    "--max-time", "$TimeoutSec",
    "--request", "POST",
    "--data", "access_token=$Token",
    "--data", "account_id=$AccountId"
  )
  if ($ParentFolderId) {
    $curlArgs += @("--data", "parent_folder_id=$ParentFolderId")
  }
  $curlArgs += "https://www.udrop.com/api/v2/folder/listing"

  try {
    $raw = & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
      throw "curl listing failed with exit code $LASTEXITCODE."
    }
    return $raw | ConvertFrom-Json
  } catch {
    throw "uDrop curl listing failed: $($_.Exception.Message)"
  }
}

if (-not $Key1 -or -not $Key2) {
  throw "Provide UDROP_KEY1 and UDROP_KEY2 as parameters or environment variables."
}

$resolvedFilePath = (Resolve-Path -LiteralPath $FilePath).Path
$fileItem = Get-Item -LiteralPath $resolvedFilePath
$fileName = $fileItem.Name

Write-Host "Testing uDrop upload for $fileName"
Write-Host "Auth timeout: $TimeoutSec seconds"
Write-Host "API mode: $ApiMode"
Write-Host "Upload mode: $UploadMode"
if ($FolderId) {
  Write-Host "Folder ID: $FolderId"
} else {
  Write-Host "Folder ID: <root>"
}

Write-Host "Calling uDrop authorize..."
if ($ApiMode -eq "Curl") {
  $auth = Get-UdropAuthCurl -AuthKey1 $Key1 -AuthKey2 $Key2
} else {
  $auth = Get-UdropAuth -AuthKey1 $Key1 -AuthKey2 $Key2
}
$token = $auth.token
$accountId = $auth.account_id

Write-Host "uDrop auth succeeded."
Write-Host "Account ID: $accountId"

$listBody = @{
  access_token = $token
  account_id = $accountId
}
if ($FolderId) {
  $listBody.parent_folder_id = $FolderId
}

Write-Host "Listing target folder..."
if ($ApiMode -eq "Curl") {
  $listJson = Invoke-UdropListingCurl -Token $token -AccountId $accountId -ParentFolderId $FolderId
} else {
  $listJson = Invoke-RestMethod -Uri "https://www.udrop.com/api/v2/folder/listing" -Method Post -TimeoutSec $TimeoutSec -Body $listBody
}
$existing = @()
if ($listJson -and $listJson.data -and $listJson.data.files) {
  $existing = @($listJson.data.files)
}

$match = $existing | Where-Object { $_.filename -eq $fileName } | Select-Object -First 1
if ($match -and -not $ForceUpload) {
  Write-Host "File already exists on uDrop. Skipping upload."
  $match | ConvertTo-Json -Depth 10
  exit 0
}

if ($match -and $ForceUpload) {
  Write-Host "File already exists on uDrop, but -ForceUpload was supplied."
}

$uploadJson = $null

if ($UploadMode -eq "Workflow") {
  $formFields = @{
    access_token = $token
    account_id = $accountId
    upload_file = Get-Item -LiteralPath $resolvedFilePath
  }
  if ($FolderId) {
    $formFields.folder_id = $FolderId
  }

  Write-Host "Uploading via the same PowerShell -Form path used by the workflow..."
  try {
    $uploadJson = Invoke-RestMethod `
      -Uri "https://www.udrop.com/api/v2/file/upload" `
      -Method Post `
      -Form $formFields `
      -TimeoutSec ([Math]::Max(300, $TimeoutSec))
  } catch {
    Write-Host "Upload request failed: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) {
      Write-Host $_.ErrorDetails.Message
    }
    exit 1
  }
} else {
  $curlArgs = @(
    "--silent",
    "--show-error",
    "--request", "POST",
    "--form", "access_token=$token",
    "--form", "account_id=$accountId",
    "--form", "upload_file=@$resolvedFilePath"
  )
  if ($FolderId) {
    $curlArgs += @("--form", "folder_id=$FolderId")
  }

  Write-Host "Uploading via curl multipart for comparison..."
  try {
    $uploadRaw = & curl.exe "https://www.udrop.com/api/v2/file/upload" @curlArgs
    if ($LASTEXITCODE -ne 0) {
      throw "curl upload failed with exit code $LASTEXITCODE."
    }
    $uploadJson = $uploadRaw | ConvertFrom-Json
  } catch {
    Write-Host "curl upload request failed: $($_.Exception.Message)"
    exit 1
  }
}

$uploadResult = $uploadJson | ConvertTo-Json -Depth 10
Write-Host $uploadResult

if ($uploadJson._status -eq "success") {
  Write-Host "uDrop upload test completed successfully."
  exit 0
}

Write-Host "uDrop upload test completed, but the API did not report success."
exit 1
