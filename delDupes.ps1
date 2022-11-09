#region Log
$global:computerslist = $null
$global:computer = $null
$global:result = $null
$global:event=$null
$global:delete=$null
$global:duplicate=$null

$Date=Get-date -format "yyyyMMdd-HHmmss"
$logfile = "$PSScriptRoot\Dupe_Del_$($Date).log"

#Region Log
Function Log($String) {
    "[$([DateTime]::Now)]: $string" | Out-File -FilePath $logfile -Append
}
#endregion Log

$client_id = Read-Host 'Enter the Client ID: '
$api_key = Read-host 'Enter the API Key: '

$EncodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($('{0}:{1}' -f $client_id, $api_key)))
$Headers = @{'Authorization' = "Basic $($EncodedCreds)"; 'accept' = 'application/json'; 'Content-type' = 'application/json'; 'Accept-Encoding' = 'gzip, deflate'} 

#region Get Computer list
Function Computerlist {
    $list=$null
    $url="https://api.amp.cisco.com/v1/computers"
    Log "Retrieving Computers list"
    $list = Invoke-RestMethod -Method Get -Uri $url -Headers $Headers -ErrorVariable RestError -ErrorAction SilentlyContinue
    if ($RestError){
        $HttpStatusCode = $RestError.ErrorRecord.Exception.Response.StatusCode.value__
        $HttpStatusDescription = $RestError.ErrorRecord.Exception.Response.StatusDescription
        Log "   - Unable to retrieve the computer list"
        Log  "  - Http Status Code: $($HttpStatusCode) - Http Status Description: $($HttpStatusDescription)"
        Log "Exiting the script"
        Exit
    }
    $global:computerslist = $list.data
    Log "Number of computers retrieved : $($computerslist.Count)"
    do {
        $url=$list.metadata.links.next
        $list = Invoke-RestMethod -Method Get -Uri $url -Headers $Headers -ErrorVariable RestError -ErrorAction SilentlyContinue
        if ($RestError){
            $HttpStatusCode = $RestError.ErrorRecord.Exception.Response.StatusCode.value__
            $HttpStatusDescription = $RestError.ErrorRecord.Exception.Response.StatusDescription
            Log "   - Unable to retrieve the computer list"
            Log  "  - Http Status Code: $($HttpStatusCode) - Http Status Description: $($HttpStatusDescription)"
            Log "Exiting the script"
            Exit
        }
        $global:computerslist += $list.data
        Log "Number of computers retrieved : $($computerslist.Count)"
    } while ($null -ne $list.metadata.links.next)
    Log "Total Retrieved: $($List.metadata.results.total)"
}
#endregion list computers

#region Delete computers
Function Delete_Computer {
    foreach ($connector in $global:delete) {
        If ($connector.hostname -ne "keepthisconnector.tdomain.com"){ #if you want some to be excluded from the deletion
            $url = $url="https://api.amp.cisco.com/v1/computers/"+$connector.connector_guid
            Log "Deleting $($connector.hostname) - $($connector.connector_guid)"
            $Response = Invoke-RestMethod -Method Delete -Uri $url -Headers $Headers -ErrorVariable RestError -ErrorAction SilentlyContinue
            if ($RestError){
                $HttpStatusCode = $RestError.ErrorRecord.Exception.Response.StatusCode.value__
                $HttpStatusDescription = $RestError.ErrorRecord.Exception.Response.StatusDescription
                Log  "  - Http Status Code: $($HttpStatusCode) - Http Status Description: $($HttpStatusDescription)"
            }
            Else {Log "   - $($connector.hostname) deleted : $($response.data.deleted)"}
        }
    }
}
#endregion Delete_Computer

#region Find_duplicate
function Delete_Duplicate {
    $temp=@()
    $list=$null
    $global:duplicate=@()
    Computerlist
    $list = $global:computerslist.hostname |Sort-Object
    $ht = @{}
    $list | ForEach-Object {$ht["$_"] += 1}
    $ht.keys | Where-Object {$ht["$_"] -gt 1} | ForEach-Object {$global:duplicate+= $_ }
    $global:duplicate = $global:duplicate|Sort-Object
    Log "Found $($global:duplicate.count) duplicate "
    foreach ($connector in $global:duplicate) {
        $temp = $global:computerslist.where({$_.hostname -like $connector})
        $count = $temp.count -1
        $global:delete = $temp | Sort-Object { $_.last_seen -as [datetime] } -Descending  | Select-Object -Last $count
        $global:delete
        Delete_Computer
    }
}
#endregion

#################### Delete connector not seen the past 10 days ###################
    # $Date_Last_seen = Get-Date -date $(Get-Date).AddDays(-10) -Format u
    # Computerlist
    # $global:delete = $global:computerslist.where({$_.last_seen -lt $Date_Last_seen -and $_.hostname -ne "keepthisconnecotr.domain.com"})
    # If ($global:delete) {
    #     Log "Starting deletion of $($global:delete.count) connectors"
    #     Delete_Computer
    # } Else {Log "No computer found with this 10 days filter"}

Delete_Duplicate