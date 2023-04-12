param ($roleName)

$roleName = $roleName.Replace("`"", "")

try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity | Out-Null
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

Write-Output ("Looking to sync any assignments of '$roleName' on resource groups attached to AKS clusters.")

$subs = Get-AzSubscription

Write-Output ("$($subs.Count) Subscriptions found ..")

foreach ($subscription in $subs) {
    Set-AzContext -Subscription $subscription.Id | Out-Null
    Write-Output ("Scanning subscription [$($subscription.Name)] .. ")
    $clusters = Get-AzAksCluster
    Write-Output ("$($clusters.Count) AKS Clusters found ..")
    foreach ($cluster in $clusters) {
        Write-Output ("... Cluster [$($cluster.Name)]")
        $parentRg = Get-AzResourceGroup -Name $cluster.ResourceGroupName
        $nodeRg = Get-AzResourceGroup -Name $cluster.NodeResourceGroup

        $parentRg_RoleAssignment = Get-AzRoleAssignment -Scope $parentRg.ResourceId -RoleDefinitionName $roleName
        $nodeRg_RoleAssignment = Get-AzRoleAssignment -Scope $nodeRg.ResourceId -RoleDefinitionName $roleName

        # Write-Output ("... Cluster [$($cluster.Name)] Found [$($parentRg_RoleAssignment.Count)] role assignments ..")
        foreach ($a in $parentRg_RoleAssignment) {
            $found = $false;
            foreach ($o in $nodeRg_RoleAssignment) {
                if ($a.ObjectId -eq $o.ObjectId) {
                    $found = $true;
                    Write-Output ("...... Role [$roleName] already assigned to [$($a.ObjectId)] <$($a.ObjectType)>")
                    break;
                }
            }
            if ($false -eq $found) {
                # role assignment from parent not found on Node Resource Group - Add it
                try {
                    New-AzRoleAssignment `
                        -Scope $nodeRg.ResourceId `
                        -RoleDefinitionName $a.RoleDefinitionName `
                        -ObjectId $a.ObjectId `
                        -ObjectType $a.ObjectType `
                        -Description "AUTOMATED" | Out-Null
                    Write-Output ("...... $($a.ObjectId) <$($a.ObjectType)> granted '$roleName' over '$($nodeRg.ResourceGroupName)'")
                } catch {
                    Write-Error ("Failed to create role assignment for $($a.ObjectId) over scope $($nodeId.Id)")
                    Write-Error -Message $_.Exception
                }
            }
        }

        # Write-Output ("... Removing any automated role assignments that should not belong ... ")
        foreach ($o in $nodeRg_RoleAssignment | Where-Object { $_.Description -match "AUTOMATED" }) {
            $found = $false;
            foreach ($a in $parentRg_RoleAssignment) {
                if ($a.ObjectId -eq $o.ObjectId) {
                    $found = $true;
                    break;
                }
            }
            if ($false -eq $found) {
                Remove-AzRoleAssignment `
                    -Scope $o.Scope `
                    -RoleDefinitionName $roleName `
                    -ObjectId $o.ObjectId | Out-Null
                Write-Output ("...... Removed '$roleName' from $($a.ObjectId) <$($a.ObjectType)> over '$($nodeRg.ResourceGroupName)'")
            }
        }
        Write-Output ("... Cluster [$($cluster.Name)] ... Done!")
    }
    Write-Output ("Subscription [$($subscription.Name)] ... Done!")
}
Resolve-AzError