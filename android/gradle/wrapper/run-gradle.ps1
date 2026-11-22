$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$GradleVersion = '8.12'
$ExpectedSha256 = '7a00d51fb93147819aab76024feece20b6b84e420694101f276be952e08bef03'
$DistributionUrl = 'https://services.gradle.org/distributions/gradle-8.12-bin.zip'

$GradleUserHome = $env:GRADLE_USER_HOME
if ([string]::IsNullOrWhiteSpace($GradleUserHome)) {
    $GradleUserHome = Join-Path $env:USERPROFILE '.gradle'
}
$WrapperDists = Join-Path $GradleUserHome 'wrapper\dists'

# Prefer a Gradle 8.12 distribution already cached by another project.
$GradleCommand = $null
if (Test-Path $WrapperDists) {
    $Cached = Get-ChildItem -Path $WrapperDists -Filter 'gradle.bat' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\gradle-8\.12\\bin\\gradle\.bat$' } |
        Select-Object -First 1
    if ($null -ne $Cached) {
        $GradleCommand = $Cached.FullName
    }
}

# If Gradle 8.12 is available on PATH, use it as another existing installation.
if ([string]::IsNullOrWhiteSpace($GradleCommand)) {
    $PathGradle = Get-Command 'gradle' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $PathGradle -and -not [string]::IsNullOrWhiteSpace($PathGradle.Source)) {
        $VersionOutput = (& $PathGradle.Source --version 2>&1 | Out-String)
        if ($VersionOutput -match '(?m)^Gradle 8\.12(?:\s|$)') {
            $GradleCommand = $PathGradle.Source
        }
    }
}

# Download only when no usable local Gradle 8.12 installation exists.
if ([string]::IsNullOrWhiteSpace($GradleCommand)) {
    $TargetRoot = Join-Path $WrapperDists 'road_guard\gradle-8.12'
    $DistributionFolder = Join-Path $TargetRoot 'gradle-8.12'
    $ZipPath = Join-Path $TargetRoot 'gradle-8.12-bin.zip'
    $ExpectedGradleBat = Join-Path $DistributionFolder 'bin\gradle.bat'

    New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null

    if (Test-Path $ExpectedGradleBat) {
        $GradleCommand = $ExpectedGradleBat
    }
    else {
        $Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (-not (Test-Path $Curl)) {
            throw 'curl.exe was not found. Install/use Windows 10 curl or configure Gradle 8.12 on PATH.'
        }

        $Downloaded = $false
        for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
            if (Test-Path $ZipPath) {
                Remove-Item -LiteralPath $ZipPath -Force
            }

            [Console]::Error.WriteLine("Downloading Gradle $GradleVersion (attempt $Attempt of 3)...")
            & $Curl --fail --location --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 900 --output $ZipPath $DistributionUrl
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ZipPath)) {
                [Console]::Error.WriteLine('Download failed. Retrying...')
                Start-Sleep -Seconds (2 * $Attempt)
                continue
            }

            $ActualSha256 = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($ActualSha256 -ne $ExpectedSha256) {
                [Console]::Error.WriteLine("Gradle ZIP checksum mismatch. Expected $ExpectedSha256 but received $ActualSha256. Retrying...")
                Remove-Item -LiteralPath $ZipPath -Force
                Start-Sleep -Seconds (2 * $Attempt)
                continue
            }

            try {
                Expand-Archive -LiteralPath $ZipPath -DestinationPath $TargetRoot -Force
                if (-not (Test-Path $ExpectedGradleBat)) {
                    throw 'The downloaded ZIP did not contain the expected gradle-8.12/bin/gradle.bat file.'
                }
                Remove-Item -LiteralPath $ZipPath -Force
                $Downloaded = $true
                $GradleCommand = $ExpectedGradleBat
                break
            }
            catch {
                [Console]::Error.WriteLine("Gradle ZIP extraction failed: $($_.Exception.Message)")
                if (Test-Path $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
                if (Test-Path $DistributionFolder) { Remove-Item -LiteralPath $DistributionFolder -Recurse -Force }
                Start-Sleep -Seconds (2 * $Attempt)
            }
        }

        if (-not $Downloaded -and [string]::IsNullOrWhiteSpace($GradleCommand)) {
            throw 'Could not obtain a verified Gradle 8.12 distribution after 3 attempts. Check internet/proxy/antivirus access to services.gradle.org.'
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GradleCommand) -or -not (Test-Path $GradleCommand)) {
    throw 'A valid Gradle 8.12 executable could not be found.'
}

# The batch launcher reads only this final line from standard output.
[Console]::Out.WriteLine($GradleCommand)
