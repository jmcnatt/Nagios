<#
	.SYNOPSIS
		Checks a Windows service health, CPU utilization, memory, and paging faults.
	
	.DESCRIPTION
		A detailed description of the Check_Test.ps1 file.
	
	.PARAMETER Name
		The name of the service to check.
	
	.PARAMETER CpuPercentWarn
		The CPU utilization percentage that will trigger a warning event.
	
	.PARAMETER CpuPercentCrit
		The CPU utilization percentage that will trigger a critical event.
	
	.PARAMETER MemWarn
		The about of memory used by the service that will trigger a warning event.
	
	.PARAMETER MemCrit
		The about of memory used by the service that will trigger a critical event.
	
	.PARAMETER FaultWarn
		The number of page faults that will trigger a warning event.
	
	.PARAMETER FaultCrit
		The numbe of page faults that will trigger a critical event.
	
	.EXAMPLE
		PS C:\> .Check_Test.ps1 -Name 'Value1' -CpuPercentWarn $value2
	
	.LINK
		https://nagios-plugins.org/doc/guidelines.html#AEN200

	.NOTES
		Additional information about the file.
#>
param
(
	[parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
	[String]$Name,

	[Parameter(Position = 1, Mandatory = $false, ValueFromPipeline = $false)]
	[int]$CpuPercentWarn,

	[Parameter(Position = 2, Mandatory = $false, ValueFromPipeline = $false)]
	[int]$CpuPercentCrit,

	[Parameter(Position = 3, Mandatory = $false, ValueFromPipeline = $false)]
	[int]$MemWarn,

	[Parameter(Position = 4, Mandatory = $false, ValueFromPipeline = $false)]
	[int]$MemCrit,

	[Parameter(Position = 5, Mandatory = $false, ValueFromPipeline = $false)]
	[int]$FaultWarn,

	[Parameter(Position = 6, Mandatory = $false, ValueFromPipeline = $false)]
	[int]$FaultCrit
)

begin
{
	<#
		.SYNOPSIS
			Prints a message and exits with code 0
		
		.DESCRIPTION
			Prints a message, which could include performance data, along with the initial
			declaration of "OK." Exits the script with a return code of 0.
		
		.PARAMETER Message
			The message to print after the initial declaration of "OK -".
		
		.EXAMPLE
			Return-Ok -Message 'CPU Utilization: 10%'
		
		.NOTES
			Conforms with Nagios standard exit 0 on OK.
	#>
	function Return-Ok
	{
		param
		(
			[parameter(Mandatory = $true)]
			[String]$Message
		)
		
		Write-Host "OK - $Message"
		exit 0
	}
	
	<#
		.SYNOPSIS
			Prints a message and exits with code 1
		
		.DESCRIPTION
			Prints a message, which could include performance data, along with the initial
			declaration of "WARNING." Exits the script with a return code of 1.
		
		.PARAMETER Message
			The message to print after the initial declaration of "WARNING -".
		
		.EXAMPLE
			Return-Warning -Message 'CPU Utilization: 70%'
		
		.NOTES
			Conforms with Nagios standard exit 1 on WARNING.
	#>
	function Return-Warning
	{
		param
		(
			[parameter(Mandatory = $true)]
			[String]$Message
		)
		
		Write-Host "WARNING - $Message"
		exit 1
	}
	
	<#
		.SYNOPSIS
			Prints a message and exits with code 2
		
		.DESCRIPTION
			Prints a message, which could include performance data or error messages, along with the initial
			declaration of "CRITICAL." Exits the script with a return code of 0.
		
		.PARAMETER Message
			The message to print after the initial declaration of "CRITICAL -".
		
		.EXAMPLE
			Return-Critical -Message 'CPU Utilization: 100%'
		
		.NOTES
			Conforms with Nagios standard exit 2 on CRITICAL.
	#>
	function Return-Critical
	{
		param
		(
			[parameter(Mandatory = $true)]
			[String]$Message
		)
		
		Write-Host "CRITICAL - $Message"
		exit 2
	}
	
	<#
		.SYNOPSIS
			Prints a message and exits with code 3
		
		.DESCRIPTION
			Prints a message, which could include debug info, along with the initial
			declaration of "UNKNOWN." Exits the script with a return code of 3.
		
		.PARAMETER Message
			The message to print after the initial declaration of "UNKNOWN -".
		
		.EXAMPLE
			Return-Unknown -Message 'There was an internal script error.'
		
		.NOTES
			Conforms with Nagios standard exit 3 on UNKNOWN.
	#>
	function Return-Unknown
	{
		param
		(
			[parameter(Mandatory = $true)]
			[String]$Message
		)
		
		Write-Host "UNKNOWN - $Message"
		exit 3
	}
}

process
{
	$Service = Get-WmiObject -Class win32_service -Filter "Name = '$Name'" -ErrorAction SilentlyContinue
	
	# Check to make sure a service was retrieved
	if ((-not $Service) -or ($Service -eq $null))
	{
		Return-Critical "Could not find an installed service identified by $Name"
	}
	
	# Make sure only one service was retrieved
	elseif (($Service | Measure-Object).Count -gt 1)
	{
		Return-Critical "Multiple services by the name of $Name returned"
	}
	
	$Name = $Service.Name
	$State = $Service.State
	$Status = $Service.Status
	$ProcessID = $Service.ProcessId
	
	# 1. Run all checks that do not return counter data
	
	# Check to see if the desired service is running
	if ($State -notlike "Running")
	{
		Return-Critical "$Name is not running"	
	}
	
	# Check the process status - should be 'OK'
	if ($Status -notlike 'OK')
	{
		Return-Critical "$Name status is $Status"
	}
	
	# Get the Process Object for counters
	$Process = Get-Process -Id $ProcessID -ErrorAction SilentlyContinue
	
	# Check to make sure a process name was retrieved
	if ((-not $Process.ProcessName) -or ($Process.ProcessName -eq $null))
	{
		Return-Unknown "Could not find the process name for $($Service.Name)"
	}

	# Get the counters on the selected process
	[int]$CpuPercent = ((Get-Counter "\process($($Process.ProcessName))\% processor time").CounterSamples).CookedValue
	[double]$Mem = ((Get-Counter "\process($($Process.ProcessName))\working set - private").CounterSamples).CookedValue / 1024 / 1024
	[int]$Faults = ((Get-Counter "\process($($Process.ProcessName))\page faults/sec").CounterSamples).CookedValue
	
	# 2. Check the counter data against supplied values, if any
	# At this point, counter values will be returned regardless of state
	
	$CounterString = "State: $State, CPU Utilization: $CpuPercent%, Memory Utilization: " + (("{0:N2}" -f $Mem) + 'MB') + ", Faults: $Faults" + `
	"|cpu=$CpuPercent%;$CpuPercentWarn;$CpuPercentCrit;0;100" + " " + `
	"memory=" + (("{0:N2}" -f $Mem) + 'MB') + ";$MemWarn;$MemCrit;;" + " " + `
	"faults=$faults;$FaultWarn;$FaultCrit;;"
	
	
	if ($CpuPercentCrit -and ($CpuPercent -ge $CpuPercentCrit))
	{
		Return-Critical $CounterString
	}
	
	if ($CpuPercentWarn -and ($CpuPercent -ge $CpuPercentWarn))
	{
		Return-Warning $CounterString
	}
	
	if ($MemCrit -and ($Mem -ge $MemCrit))
	{
		Return-Critical $CounterString
	}
	
	if ($MemWarn -and ($Mem -ge $MemWarn))
	{
		Return-Warning $CounterString
	}
	
	if ($FaultCrit -and ($Faults -ge $FaultCrit))
	{
		Return-Critical $CounterString
	}
	
	if ($FaultWarn -and ($Faults -ge $FaultWarn))
	{
		Return-Warning $CounterString
	}
	
	# 3. If no checks trigger a return statement, return OK
	
	Return-Ok $CounterString
}