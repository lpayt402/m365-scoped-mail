#Requires -Version 5.1
<#
.SYNOPSIS
Read-only Exchange Application RBAC validation for one approved mailbox.
.DESCRIPTION
Run in an existing, single-tenant, unprefixed Exchange Online V3 administrator
session. No sign-in, permission changes, token acquisition, or mail sending occurs.
Throws on failed/incomplete checks. Success still requires Entra permission review
and explicitly authorized live Graph positive/negative testing before activation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][guid]$ClientId,
    [Parameter(Mandatory)][guid]$ServicePrincipalObjectId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ScopeName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$AuthorizedMailbox,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$DeniedMailbox
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\M365ScopedMail.Validation.psm1') -Force -ErrorAction Stop
Invoke-M365ScopedMailValidation @PSBoundParameters
