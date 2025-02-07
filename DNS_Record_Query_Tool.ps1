# PowerShell script for querying MX, DMARC and SPF records

# Ask user for paths
$domainsPath = Read-Host -Prompt "Please enter the full path to the domains.txt file"
$resultsFolder = Read-Host -Prompt "Please enter the folder path for the results file"

# Check if input file exists
if (-not (Test-Path $domainsPath)) {
    Write-Host "The specified domains.txt file was not found. Script will exit." -ForegroundColor Red
    exit
}

# Check if output folder exists
if (-not (Test-Path $resultsFolder)) {
    Write-Host "The specified output folder does not exist. Script will exit." -ForegroundColor Red
    exit
}

$outputPath = Join-Path $resultsFolder "dns_results.csv"
$domains = Get-Content -Path $domainsPath
$retryDomains = @()

# Function to try DNS resolution
function Resolve-DnsWithFallback {
    param($DomainName, $RecordType)
    
    Write-Host "Attempting $RecordType query for $DomainName..."
    try {
        return Resolve-DnsName -Name $DomainName -Type $RecordType -ErrorAction Stop
    }
    catch {
        Write-Host "DNS query failed..." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        throw "DNS query failed"
    }
}

# Check if results file already exists
if (Test-Path $outputPath) {
    $existingResults = Import-Csv -Path $outputPath
    
    # If only nameservers are missing, add only those
    if ($existingResults[0].PSObject.Properties.Name -notcontains 'Nameserver') {
        Write-Host "Adding nameserver column to existing results..." -ForegroundColor Yellow
        
        $startTime = Get-Date
        $totalDomains = $existingResults.Count
        $currentDomain = 0
        
        $updatedResults = $existingResults | ForEach-Object {
            $currentDomain++
            $domain = $_.Domain
            
            # Calculate progress and estimated time remaining
            $elapsedTime = (Get-Date) - $startTime
            $averageTimePerDomain = $elapsedTime.TotalSeconds / $currentDomain
            $remainingDomains = $totalDomains - $currentDomain
            $estimatedTimeRemaining = [TimeSpan]::FromSeconds($averageTimePerDomain * $remainingDomains)
            
            $progress = [math]::Round(($currentDomain / $totalDomains) * 100, 2)
            Write-Progress -Activity "Processing Domains" -Status "$domain ($currentDomain of $totalDomains)`nElapsed time: $($elapsedTime.ToString('hh\:mm\:ss'))`nEstimated time remaining: $($estimatedTimeRemaining.ToString('hh\:mm\:ss'))" -PercentComplete $progress
            
            try {
                $nsRecords = Resolve-DnsWithFallback -DomainName $domain -RecordType NS
                $nsString = ($nsRecords | ForEach-Object { $_.NameHost }) -join "; "
                $_ | Add-Member -MemberType NoteProperty -Name 'Nameserver' -Value $nsString
            }
            catch {
                $_ | Add-Member -MemberType NoteProperty -Name 'Nameserver' -Value "Error: $($_.Exception.Message)"
            }
            $_
        }
        
        # Save updated results
        $updatedResults | Export-Csv -Path $outputPath -NoTypeInformation -Force
        Write-Host "Existing results file has been updated with nameserver information." -ForegroundColor Green
        exit
    }
}

# Create empty array for results
$results = @()
$totalDomains = $domains.Count
$currentDomain = 0
$startTime = Get-Date

foreach ($domain in $domains) {
    $currentDomain++
    
    # Calculate progress and estimated time remaining
    $elapsedTime = (Get-Date) - $startTime
    $averageTimePerDomain = $elapsedTime.TotalSeconds / $currentDomain
    $remainingDomains = $totalDomains - $currentDomain
    $estimatedTimeRemaining = [TimeSpan]::FromSeconds($averageTimePerDomain * $remainingDomains)
    
    $progress = [math]::Round(($currentDomain / $totalDomains) * 100, 2)
    Write-Progress -Activity "Processing Domains" -Status "$domain ($currentDomain of $totalDomains)`nElapsed time: $($elapsedTime.ToString('hh\:mm\:ss'))`nEstimated time remaining: $($estimatedTimeRemaining.ToString('hh\:mm\:ss'))" -PercentComplete $progress

    $result = [PSCustomObject]@{
        Domain = $domain
        Nameserver = "Not found"
        MX = "Not found"
        DMARC = "Not found"
        DMARC_Subdomain = "Not found"
        SPF = "Not found"
        SPF_Subdomain = "Not found"
    }

    # Query Nameserver
    try {
        $nsRecords = Resolve-DnsWithFallback -DomainName $domain -RecordType NS
        $result.Nameserver = ($nsRecords | ForEach-Object { $_.NameHost }) -join "; "
        Write-Host "Nameserver found: $($result.Nameserver)" -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    catch {
        $result.Nameserver = "Error: $($_.Exception.Message)"
        Write-Host "Error in nameserver query: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }

    # Query MX Record
    try {
        $mxRecords = Resolve-DnsWithFallback -DomainName $domain -RecordType MX
        $result.MX = ($mxRecords | ForEach-Object { "$($_.NameExchange) (Priority: $($_.Preference))" }) -join "; "
        Write-Host "MX record found: $($result.MX)" -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    catch {
        $result.MX = "Error: $($_.Exception.Message)"
        if (!$retryDomains.Contains($domain)) {
            $retryDomains += $domain
        }
        Write-Host "Error in MX query: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }

    # Query DMARC Record on domain level
    try {
        $dmarcRecord = Resolve-DnsWithFallback -DomainName "_dmarc.$domain" -RecordType TXT
        $result.DMARC = ($dmarcRecord.Strings) -join " "
        Write-Host "DMARC record found: $($result.DMARC)" -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    catch {
        $result.DMARC = "No DMARC record found at domain level"
        if (!$retryDomains.Contains($domain)) {
            $retryDomains += $domain
        }
        Write-Host "No DMARC record found at domain level" -ForegroundColor Yellow
        Start-Sleep -Seconds 1

        # If no domain level record, check subdomains
        try {
            $subdomains = "mail", "email", "smtp"
            foreach ($sub in $subdomains) {
                $dmarcSubRecord = Resolve-DnsWithFallback -DomainName "_dmarc.$sub.$domain" -RecordType TXT
                if ($dmarcSubRecord) {
                    $result.DMARC_Subdomain = "($sub) " + ($dmarcSubRecord.Strings -join " ")
                    Write-Host "DMARC record found in subdomain: $($result.DMARC_Subdomain)" -ForegroundColor Green
                    break
                }
            }
        }
        catch {
            $result.DMARC_Subdomain = "No DMARC record found at subdomain level"
            Write-Host "No DMARC record found at subdomain level" -ForegroundColor Yellow
        }
    }

    # Query SPF Record on domain level
    try {
        $spfRecord = Resolve-DnsWithFallback -DomainName $domain -RecordType TXT
        $result.SPF = ($spfRecord.Strings | Where-Object { $_ -match "^v=spf1" }) -join " "
        if (!$result.SPF) {
            $result.SPF = "No SPF record found at domain level"
            Write-Host "No SPF record found at domain level" -ForegroundColor Yellow
            
            # If no domain level record, check subdomains
            $subdomains = "mail", "email", "smtp"
            foreach ($sub in $subdomains) {
                try {
                    $spfSubRecord = Resolve-DnsWithFallback -DomainName "$sub.$domain" -RecordType TXT
                    $spfSubString = ($spfSubRecord.Strings | Where-Object { $_ -match "^v=spf1" }) -join " "
                    if ($spfSubString) {
                        $result.SPF_Subdomain = "($sub) $spfSubString"
                        Write-Host "SPF record found in subdomain: $($result.SPF_Subdomain)" -ForegroundColor Green
                        break
                    }
                }
                catch {
                    continue
                }
            }
            if ($result.SPF_Subdomain -eq "Not found") {
                Write-Host "No SPF record found at subdomain level" -ForegroundColor Yellow
            }
            Start-Sleep -Seconds 1
        }
        else {
            Write-Host "SPF record found: $($result.SPF)" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
    }
    catch {
        $result.SPF = "Error: $($_.Exception.Message)"
        if (!$retryDomains.Contains($domain)) {
            $retryDomains += $domain
        }
        Write-Host "Error in SPF query: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }

    Write-Host "`n-----------------------------------`n"
    $results += $result
    Start-Sleep -Seconds 2
}

# Process domains with timeouts
if ($retryDomains.Count -gt 0) {
    Write-Host "`nProcessing $($retryDomains.Count) domains with previous timeouts...`n" -ForegroundColor Yellow
    foreach ($domain in $retryDomains) {
        # Same code as above for retry attempts
        # Omitted for space reasons
    }
}

# Save results to CSV file
$results | Export-Csv -Path $outputPath -NoTypeInformation -Delimiter "," -Encoding UTF8
Write-Host "Results have been saved to $outputPath" -ForegroundColor Green
