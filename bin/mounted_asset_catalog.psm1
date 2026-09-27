Set-StrictMode -Version Latest

function ConvertTo-CatalogModelPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $model = $Path.Trim().Replace('\', '/').ToLowerInvariant()
    if ($model -notmatch '^models/.+\.mdl$') {
        return $null
    }
    return $model
}

function Test-CatalogCandidateModel {
    param([string]$Model)

    $canonical = ConvertTo-CatalogModelPath $Model
    if (-not $canonical) {
        return $false
    }
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($canonical)
    if ($fileName -match '(_chunk\d*|_door|_wheel[lr]?|_base|_top|_left|_right)$') {
        return $false
    }
    if ($canonical -match '^models/(items|food)/' -or $canonical -match '^models/weapons/w_') {
        return $true
    }
    if ($canonical -notmatch '^models/props(?:_[^/]+)?/') {
        return $false
    }
    if ($fileName -match '(ammo|vending|crate|dumpster|food|health|medical|medkit|cash|money|barrel|oil|water|ration|bottle|can|soda|popcan|meat|fruit|fish|bird|plant|tool|wire|metal|gascan|crowbar|shovel|hammer|axe|knife|briefcase)') {
        return $true
    }
    return $false
}

function Get-CatalogModelMetadata {
    param([string]$Model)

    $canonical = ConvertTo-CatalogModelPath $Model
    $family = 'prop'
    if ($canonical -match '(ammo|ammocrate|ammunition)') {
        $family = 'ammunition'
    } elseif ($canonical -match '^models/props_vehicles/') {
        $family = 'vehicle'
    } elseif ($canonical -match '/weapons/') {
        $family = 'weapon'
    } elseif ($canonical -match '(vending|crate|barrel|dumpster)') {
        $family = 'container'
    } elseif ($canonical -match '(food|meat|fruit|fish|bird|soda|popcan|bottle|milkcarton|watermelon|orange|potato|carrot|tomato)') {
        $family = 'food'
    } elseif ($canonical -match '(health|medical|medkit|syringe|bandage)') {
        $family = 'medical'
    } elseif ($canonical -match '(cash|money)') {
        $family = 'currency'
    } elseif ($canonical -match '(metal|wire|tool|gascan|crowbar|shovel|hammer|axe|knife)') {
        $family = 'materials'
    }

    $tags = [System.Collections.Generic.List[string]]::new()
    foreach ($tag in @('ammo', 'vending', 'crate', 'barrel', 'dumpster', 'vehicle', 'weapon', 'food', 'medical', 'cash', 'water', 'oil', 'tool', 'metal')) {
        if ($canonical.Contains($tag)) {
            $tags.Add($tag)
        }
    }
    if ($canonical -match '^models/items/') {
        $tags.Add('items-folder')
    } elseif ($canonical -match '^models/props/') {
        $tags.Add('props-folder')
    } elseif ($canonical -match '^models/weapons/') {
        $tags.Add('weapons-folder')
    }

    return [pscustomobject]@{
        assetFamily = $family
        tags = @($tags | Sort-Object -Unique)
    }
}

function Merge-CatalogModelEntries {
    param(
        [object[]]$ArchiveEntries = @(),
        [object[]]$References = @()
    )

    $records = @{}
    foreach ($entry in $ArchiveEntries) {
        $model = ConvertTo-CatalogModelPath $entry.model
        if (-not $model) {
            continue
        }
        if (-not $records.ContainsKey($model)) {
            $metadata = Get-CatalogModelMetadata $model
            $records[$model] = [ordered]@{
                model = $model
                assetFamily = $metadata.assetFamily
                tags = @($metadata.tags)
                sourceArchives = [System.Collections.Generic.List[string]]::new()
                mounted = $false
                suitableForItem = $false
                references = [System.Collections.Generic.List[string]]::new()
            }
        }

        $record = $records[$model]
        if ($entry.sourceArchive -and -not $record.sourceArchives.Contains([string]$entry.sourceArchive)) {
            $record.sourceArchives.Add([string]$entry.sourceArchive)
        }
        if ($entry.mounted) {
            $record.mounted = $true
        }
    }

    foreach ($reference in $References) {
        $model = ConvertTo-CatalogModelPath $reference.model
        if (-not $model) {
            continue
        }
        if (-not $records.ContainsKey($model)) {
            $metadata = Get-CatalogModelMetadata $model
            $records[$model] = [ordered]@{
                model = $model
                assetFamily = $metadata.assetFamily
                tags = @($metadata.tags)
                sourceArchives = [System.Collections.Generic.List[string]]::new()
                mounted = $false
                suitableForItem = $false
                references = [System.Collections.Generic.List[string]]::new()
            }
        }

        $record = $records[$model]
        $referenceLabel = '{0}:{1}' -f $reference.itemId, $reference.usage
        if (-not $record.references.Contains($referenceLabel)) {
            $record.references.Add($referenceLabel)
        }
        if ($reference.usage -in @('iconModel', 'worldModel', 'fallbackIcon')) {
            $record.suitableForItem = $true
        }
    }

    $result = foreach ($model in ($records.Keys | Sort-Object)) {
        $record = $records[$model]
        [pscustomobject]@{
            model = $record.model
            sourceArchives = @($record.sourceArchives | Sort-Object)
            assetFamily = $record.assetFamily
            tags = @($record.tags | Sort-Object -Unique)
            mounted = [bool]$record.mounted
            suitableForItem = [bool]$record.suitableForItem
            references = @($record.references | Sort-Object)
        }
    }
    return @($result)
}

Export-ModuleMember -Function ConvertTo-CatalogModelPath, Test-CatalogCandidateModel, Get-CatalogModelMetadata, Merge-CatalogModelEntries
