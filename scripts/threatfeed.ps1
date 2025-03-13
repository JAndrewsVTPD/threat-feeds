# =============================
# Configuration
# =============================

# Set up the working directory inside the GitHub Actions workspace.
$destDir = "$env:GITHUB_WORKSPACE\temp"
if (!(Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir | Out-Null
}

# Feed 1: Threat feed (IPs)
$threatFeedUrl1 = "https://raw.githubusercontent.com/stamparm/ipsum/master/ipsum.txt"
$tempFile1      = "$destDir\ipsum.txt"
$outputFile1    = "$destDir\URLhaus_IPs.txt"  # Output file for IP addresses

# Feed 2: URLhaus recent feed (domains)
$threatFeedUrl2 = "https://urlhaus.abuse.ch/downloads/text_recent/"
$tempFile2      = "$destDir\urlhaus_recent.txt"
$outputFile2    = "$destDir\URLhaus_domains.txt"  # Output file for domains

# GitHub repository details
$githubRepo      = "JAndrewsVTPD/threat-feeds"
$githubBranch    = "main"
$githubFilePath1 = "URLhaus_IPs.txt"      # File in the repo for IP addresses
$githubFilePath2 = "URLhaus_domains.txt"  # File in the repo for domains
$githubToken     = $env:MY_GITHUB_TOKEN   # Your token from GitHub Secrets

# Exclusion list for domain names (domains to not include in the output)
$excludedDomains = @("github.com", "drive.google.com")

# =============================
# Step 1: Download the Threat Feed
# =============================
Write-Output "Downloading threat feed from $threatFeedUrl1..."
Invoke-WebRequest -Uri $threatFeedUrl1 -OutFile $tempFile1

# =============================
# Step 2: Extract the IP Addresses
# =============================
Write-Output "Extracting IP addresses from the downloaded file..."
$ipAddresses = Get-Content $tempFile1 | ForEach-Object {
    $line = $_.Trim()
    if (-not $line.StartsWith("#") -and $line.Length -gt 0) {
        $fields = $line -split "\s+"
        if ($fields.Count -ge 1) {
            # Output the first element (the IP address)
            $fields[0]
        }
    }
}
Write-Output "Removing Duplicate entries..."
# Deduplicate using a hash table
$uniqueIPs = @{}
foreach ($ip in $ipAddresses) {
    if ($ip -and (-not $uniqueIPs.ContainsKey($ip))) {
        $uniqueIPs[$ip] = $true
    }
}
$ipAddressesUnique = $uniqueIPs.Keys

# =============================
# Step 3: Save the Extracted IP Addresses
# =============================
if (Test-Path $outputFile1) { Remove-Item $outputFile1 -Force }
$ipAddressesUnique | Out-File -FilePath $outputFile1 -Encoding UTF8
Write-Output "Extraction complete. IP addresses saved to $outputFile1"

# =============================
# Part 2: Process Feed 2 (Domains)
# =============================
Write-Output "Downloading URLhaus recent feed from $threatFeedUrl2..."
Invoke-WebRequest -Uri $threatFeedUrl2 -OutFile $tempFile2

Write-Output "Extracting domain names from the downloaded file..."
$domains = Get-Content $tempFile2 | ForEach-Object {
    $line = $_.Trim()
    if ($line -match "^(http[s]?://)?([^/:]+)") {
        $domainName = $matches[2]
        if (($domainName -notmatch "^\d{1,3}(\.\d{1,3}){3}$") -and ($excludedDomains -notcontains $domainName)) {
            $domainName
        }
    }
}
Write-Output "Removing Duplicate entries..."
$uniqueDomains = @{}
foreach ($domain in $domains) {
    if ($domain -and (-not $uniqueDomains.ContainsKey($domain))) {
        $uniqueDomains[$domain] = $true
    }
}
$domainsUnique = $uniqueDomains.Keys

if (Test-Path $outputFile2) { Remove-Item $outputFile2 -Force }
$domainsUnique | Out-File -FilePath $outputFile2 -Encoding UTF8
Write-Output "Domain names saved to $outputFile2"

# =============================
# Function: Upload File to GitHub
# =============================
function Upload-ToGitHub {
    param(
        [string]$localFilePath,
        [string]$repoFilePath
    )
    $fileContent = Get-Content -Path $localFilePath -Raw
    $base64Content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($fileContent))
    $apiUrl = "https://api.github.com/repos/$githubRepo/contents/$repoFilePath"
    
    Write-Output "Checking if $repoFilePath exists in the repository..."
    $currentSha = $null
    try {
        $existingFile = Invoke-RestMethod -Uri $apiUrl -Headers @{ Authorization = "token $githubToken" } -Method Get
        $currentSha = $existingFile.sha
        Write-Output "File exists. SHA: $currentSha"
    } catch {
        Write-Output "File does not exist in repository. It will be created."
    }
    
    $commitMessage = "Update $repoFilePath on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $body = @{
        message = $commitMessage
        content = $base64Content
        branch  = $githubBranch
    }
    if ($currentSha) { $body.sha = $currentSha }
    $jsonBody = $body | ConvertTo-Json

    Write-Output "Uploading $repoFilePath to GitHub..."
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers @{ Authorization = "token $githubToken" } -Method Put -Body $jsonBody -ContentType "application/json"
        Write-Output "$repoFilePath uploaded successfully."
    } catch {
        Write-Output "Failed to upload $repoFilePath to GitHub. Error details:"
        Write-Output $_.Exception.Message
    }
}

# =============================
# Part 3: Upload Both Files to GitHub
# =============================
Upload-ToGitHub -localFilePath $outputFile1 -repoFilePath $githubFilePath1
Upload-ToGitHub -localFilePath $outputFile2 -repoFilePath $githubFilePath2
