# Enhanced Test Script for WireGuard Config Updater (PowerShell version)

# Initialize error tracking
$TestFailed = $false

# Step 1: Check if 'uv' is installed
Write-Host "Checking if 'uv' is installed..."
$UV = Get-Command uv -ErrorAction SilentlyContinue
if (-not $UV) {
    Write-Host "** FAIL ** 'uv' is not installed or not in your PATH." -ForegroundColor Red
    Write-Host "Please install Astra UV from https://docs.astral.sh/uv/getting-started/installation/ and ensure it is added to your PATH."
    $TestFailed = $true
} else {
    Write-Host "** OK ** 'uv' is installed." -ForegroundColor Green
}

# Step 2: Define paths and variables
$UVScript = "main.py"
$TemplateFile = "temp_template.conf"
$OutputFile = "output.conf"
$Domain = "example.com"
$MultipleDomainsFile = "domains.txt"
$InvalidDomain = "invalid-domain.example"
$InvalidIPClass = "/48"

# Step 3: Create a temporary WireGuard template file
Write-Host "Creating temporary WireGuard template file..."
@"
[Interface]
PrivateKey = [REDACTED]=
Address = 192.168.2.1/32
DNS = 1.1.1.1

[Peer]
PublicKey = [REDACTED]=
AllowedIPs = 192.168.1.1/32, 10.0.0.0/8
Endpoint = example.com:51820
PersistentKeepalive = 25
"@ | Set-Content -Path $TemplateFile

# Step 4: Create a file with multiple domains
Write-Host "Creating a file with multiple domains..."
@"
example.com
google.com
github.com
"@ | Set-Content -Path $MultipleDomainsFile

# Step 5: Run the Python program with a single domain
Write-Host "Running test 1: Single domain '$Domain' with class '32'..."
uv run $UVScript $TemplateFile $Domain --class 32 --output $OutputFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "** FAIL ** Test 1 failed: Error running the program with a single domain." -ForegroundColor Red
    $TestFailed = $true
} else {
    Write-Host "** OK ** Test 1 passed: Successfully updated AllowedIPs with a single domain." -ForegroundColor Green
}

# Step 6: Run the Python program with multiple domains
Write-Host "Running test 2: Multiple domains from file '$MultipleDomainsFile' with class 'C'..."
uv run $UVScript $TemplateFile $MultipleDomainsFile --class C --output $OutputFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "** FAIL ** Test 2 failed: Error running the program with multiple domains." -ForegroundColor Red
    $TestFailed = $true
} else {
    Write-Host "** OK ** Test 2 passed: Successfully updated AllowedIPs with multiple domains." -ForegroundColor Green
}

# Step 7: Test with an invalid domain
Write-Host "Running test 3: Invalid domain '$InvalidDomain'..."
uv run $UVScript $TemplateFile $InvalidDomain --class 32 --output $OutputFile
if ($LASTEXITCODE -eq 0) {
    Write-Host "** FAIL ** Test 3 failed: The program should have failed with an invalid domain." -ForegroundColor Red
    $TestFailed = $true
} else {
    Write-Host "** OK ** Test 3 passed: Correctly handled invalid domain." -ForegroundColor Green
}

# Step 8: Test with an invalid IP class
Write-Host "Running test 4: Invalid IP class '$InvalidIPClass'..."
uv run $UVScript $TemplateFile $Domain --class $InvalidIPClass --output $OutputFile
if ($LASTEXITCODE -eq 0) {
    Write-Host "** FAIL ** Test 4 failed: The program should have failed with an invalid IP class." -ForegroundColor Red
    $TestFailed = $true
} else {
    Write-Host "** OK ** Test 4 passed: Correctly handled invalid IP class." -ForegroundColor Green
}

# Step 9: Test overwrite behavior
Write-Host "Running test 5: Overwrite AllowedIPs field..."

# Create a fresh template file first to ensure no previous modifications affect this test
@"
[Interface]
PrivateKey = [REDACTED]=
Address = 192.168.2.1/32
DNS = 1.1.1.1

[Peer]
PublicKey = [REDACTED]=
AllowedIPs = 192.168.1.1/32, 10.0.0.0/8
Endpoint = example.com:51820
PersistentKeepalive = 25
"@ | Set-Content -Path $TemplateFile

uv run $UVScript $TemplateFile $Domain --class 32 --output $OutputFile --overwrite
if ($LASTEXITCODE -ne 0) {
    Write-Host "** FAIL ** Test 5 failed: Error running the program with overwrite behavior." -ForegroundColor Red
    $TestFailed = $true
} else {
    $content = Get-Content -Path $OutputFile
    $originalIPsFound = $content -match "AllowedIPs = 192\.168\.1\.1/32, 10\.0\.0\.0/8"
    
    if ($originalIPsFound) {
        Write-Host "** FAIL ** Test 5 failed: Original IPs (192.168.1.1/32, 10.0.0.0/8) should NOT be present in overwrite mode!" -ForegroundColor Red
        $TestFailed = $true
    } else {
        Write-Host "** OK ** Test 5 passed: Overwrite behavior works as expected." -ForegroundColor Green
    }
}

# Step 10: Test append behavior (Append is the default)
Write-Host "Running test 6: Append to AllowedIPs field..."

# Create a fresh template file first to ensure no previous modifications affect this test
@"
[Interface]
PrivateKey = [REDACTED]=
Address = 192.168.2.1/32
DNS = 1.1.1.1

[Peer]
PublicKey = [REDACTED]=
AllowedIPs = 192.168.1.1/32, 10.0.0.0/8
Endpoint = example.com:51820
PersistentKeepalive = 25
"@ | Set-Content -Path $TemplateFile

uv run $UVScript $TemplateFile $Domain --class 32 --output $OutputFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "** FAIL ** Test 6 failed: Error running the program with append behavior." -ForegroundColor Red
    $TestFailed = $true
} else {
    $content = Get-Content -Path $OutputFile
    
    # Check for the presence of resolved IPs after the original AllowedIPs
    $originalIPs = "AllowedIPs = 192.168.1.1/32, 10.0.0.0/8"
    $hasOriginalIPs = $false
    $hasResolvedIPs = $false
    $domainIPs = $content | Where-Object { $_ -match "AllowedIPs = .*example.com.*" }
    
    foreach ($line in $content) {
        if ($line.Contains($originalIPs)) {
            $hasOriginalIPs = $true
        }
        
        if ($line -match "AllowedIPs = .*\d+\.\d+\.\d+\.\d+/32.*" -and $line -ne $originalIPs) {
            $hasResolvedIPs = $true
        }
    }
    
    if ($hasOriginalIPs -and $hasResolvedIPs) {
        Write-Host "** OK ** Test 6 passed: Append behavior works as expected." -ForegroundColor Green
    } else {
        Write-Host "** FAIL ** Test 6 failed: New IPs were not appended correctly." -ForegroundColor Red
        Write-Host "Debug - Original IPs found: $hasOriginalIPs, Resolved IPs found: $hasResolvedIPs" -ForegroundColor Yellow
        $TestFailed = $true
    }
}

# Step 11: Validate the Diff between the files
Write-Host "Comparing files:"
$templateContent = Get-Content -Path $TemplateFile -Raw
$outputContent = Get-Content -Path $OutputFile -Raw

if ($templateContent -eq $outputContent) {
    Write-Host "** FAIL ** Diff failed: No changes detected in the output file." -ForegroundColor Red
    $TestFailed = $true
} else {
    Write-Host "** OK ** Diff Test Passed." -ForegroundColor Green
}

# Step 12: Test mixed domain file with different CIDR notations
Write-Host "Running test 7: Mixed domains with different CIDR notations..."
$MixedDomainsFile = "mixed_domains.txt"

# Create a file with mixed domain CIDR notations
@"
example.com
google.com,/24
github.com,/16
microsoft.com,/32
"@ | Set-Content -Path $MixedDomainsFile

# Create a fresh template file first
@"
[Interface]
PrivateKey = [REDACTED]=
Address = 192.168.2.1/32
DNS = 1.1.1.1

[Peer]
PublicKey = [REDACTED]=
AllowedIPs = 192.168.1.1/32, 10.0.0.0/8
Endpoint = example.com:51820
PersistentKeepalive = 25
"@ | Set-Content -Path $TemplateFile

# Run the script with the mixed domains file, using a default class of 'C'
uv run $UVScript $TemplateFile $MixedDomainsFile --class C --output $OutputFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "** FAIL ** Test 7 failed: Error running the program with mixed domain CIDR notations." -ForegroundColor Red
    $TestFailed = $true
} else {
    $content = Get-Content -Path $OutputFile
    
    # Look for IPs with different CIDR notations
    $hasDefaultClass = $false
    $hasClass24 = $false
    $hasClass16 = $false
    $hasClass32 = $false
    
    # Check for IPs with different CIDR notations
    # Note: We're looking for IP patterns, not domain names, as the script resolves domains to IPs
    foreach ($line in $content) {
        if ($line -match "AllowedIPs = .*\d+\.\d+\.\d+\.\d+/24") {
            $hasClass24 = $true
        }
        if ($line -match "AllowedIPs = .*\d+\.\d+\.\d+\.\d+/16") {
            $hasClass16 = $true
        }
        if ($line -match "AllowedIPs = .*\d+\.\d+\.\d+\.\d+/32") {
            $hasClass32 = $true
        }
    }
    
    # For example.com, it should use the default class 'C' which is /24
    # google.com explicitly specifies /24
    # github.com explicitly specifies /16
    # microsoft.com explicitly specifies /32
    
    if ($hasClass24 -and $hasClass16 -and $hasClass32) {
        Write-Host "** OK ** Test 7 passed: Mixed domain CIDR notations processed correctly." -ForegroundColor Green
    } else {
        Write-Host "** FAIL ** Test 7 failed: Not all CIDR notations were processed correctly." -ForegroundColor Red
        Write-Host "Debug - Class /24: $hasClass24, Class /16: $hasClass16, Class /32: $hasClass32" -ForegroundColor Yellow
        $TestFailed = $true
    }
}

# Step 13: Clean up temporary files
Write-Host "Cleaning up temporary files..."
Remove-Item -Path $TemplateFile -ErrorAction SilentlyContinue
Remove-Item -Path $OutputFile -ErrorAction SilentlyContinue
Remove-Item -Path $MultipleDomainsFile -ErrorAction SilentlyContinue
Remove-Item -Path $MixedDomainsFile -ErrorAction SilentlyContinue

# Final Exit Status
if ($TestFailed) {
    Write-Host "Some tests failed. Exiting with error status." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All tests completed successfully." -ForegroundColor Green
    exit 0
}
