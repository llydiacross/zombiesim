param(
    [string]$PlanData = '',
    [string]$NavmeshDirectory = '',
    [string]$OutputPath = '',
    [string]$WorldProfile = '',
    [switch]$Preview,
    [switch]$WhatIf,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$navVersion = 16
if (-not ('ZombieSimNavmeshReader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;

public sealed class ZombieSimNavmeshArea
{
    public float NorthWestX;
    public float NorthWestY;
    public float NorthWestZ;
    public float SouthEastX;
    public float SouthEastY;
    public float SouthEastZ;
    public float NorthEastZ;
    public float SouthWestZ;
}

public static class ZombieSimNavmeshReader
{
    private const uint Magic = 0xFEEDFACE;
    private const uint Version = 16;
    private const uint MaximumCount = 1000000;

    private static void Skip(BinaryReader reader, long count, string context)
    {
        if (count < 0 || reader.BaseStream.Position + count > reader.BaseStream.Length)
        {
            throw new InvalidDataException("Unexpected end of navmesh data while reading " + context + ".");
        }
        reader.BaseStream.Seek(count, SeekOrigin.Current);
    }

    private static uint ReadCount(BinaryReader reader, string context)
    {
        uint count = reader.ReadUInt32();
        if (count > MaximumCount)
        {
            throw new InvalidDataException("Invalid " + context + " count: " + count + ".");
        }
        return count;
    }

    public static ZombieSimNavmeshArea[] ReadAreas(string path)
    {
        using (FileStream stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        using (BinaryReader reader = new BinaryReader(stream))
        {
            if (reader.ReadUInt32() != Magic)
            {
                throw new InvalidDataException("Invalid Source navmesh magic number.");
            }
            if (reader.ReadUInt32() != Version)
            {
                throw new InvalidDataException("Unsupported Source navmesh version.");
            }
            if (reader.ReadUInt32() != 0)
            {
                throw new InvalidDataException("Unsupported Source navmesh subversion.");
            }
            Skip(reader, 5, "navmesh header");
            ushort placeCount = reader.ReadUInt16();
            for (int placeIndex = 0; placeIndex < placeCount; placeIndex++)
            {
                Skip(reader, reader.ReadUInt16(), "place name");
            }
            Skip(reader, 1, "unnamed-area marker");
            uint areaCount = ReadCount(reader, "area");
            if (areaCount == 0)
            {
                throw new InvalidDataException("Source navmesh contains no areas.");
            }

            var areas = new List<ZombieSimNavmeshArea>((int)areaCount);
            for (uint areaIndex = 0; areaIndex < areaCount; areaIndex++)
            {
                uint areaId = reader.ReadUInt32();
                Skip(reader, 4, "area attributes");
                var area = new ZombieSimNavmeshArea();
                area.NorthWestX = reader.ReadSingle();
                area.NorthWestY = reader.ReadSingle();
                area.NorthWestZ = reader.ReadSingle();
                area.SouthEastX = reader.ReadSingle();
                area.SouthEastY = reader.ReadSingle();
                area.SouthEastZ = reader.ReadSingle();
                area.NorthEastZ = reader.ReadSingle();
                area.SouthWestZ = reader.ReadSingle();
                if (area.SouthEastX < area.NorthWestX || area.SouthEastY < area.NorthWestY)
                {
                    throw new InvalidDataException("Nav area " + areaId + " has an invalid extent.");
                }

                for (int directionIndex = 0; directionIndex < 4; directionIndex++)
                {
                    Skip(reader, (long)ReadCount(reader, "connection") * 4, "connections");
                }
                Skip(reader, (long)reader.ReadByte() * 17, "hiding spots");
                uint encounterCount = ReadCount(reader, "encounter");
                for (uint encounterIndex = 0; encounterIndex < encounterCount; encounterIndex++)
                {
                    Skip(reader, 10, "encounter header");
                    Skip(reader, (long)reader.ReadByte() * 5, "encounter spots");
                }
                Skip(reader, 2, "place");
                for (int ladderDirection = 0; ladderDirection < 2; ladderDirection++)
                {
                    Skip(reader, (long)ReadCount(reader, "ladder") * 4, "ladders");
                }
                Skip(reader, 24, "occupancy and lighting");
                Skip(reader, (long)ReadCount(reader, "visible area") * 5, "visible areas");
                Skip(reader, 4, "inherited visibility");
                areas.Add(area);
            }
            return areas.ToArray();
        }
    }
}
'@
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$profileSettings = $worldGenerationProfile.Config
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $planFilePattern = "$($profileSettings.filePrefix)_grid_*_template_plan.json"
    $PlanData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $planFilePattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($PlanData) -or -not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
    throw 'A template plan is required. Pass -PlanData with a <profile>_grid_*_template_plan.json path.'
}
if ([string]::IsNullOrWhiteSpace($NavmeshDirectory)) {
    $gameRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)
    $NavmeshDirectory = Join-Path (Join-Path $gameRoot 'maps') $worldGenerationProfile.Name
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot (Join-Path (Join-Path (Join-Path 'content/materials/worlds' $worldGenerationProfile.Name) 'map_layers') 'wireframe.png')
}

$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$cells = @($plan.cells)
if ($plan.schemaVersion -lt 4 -or $cells.Count -lt 1) {
    throw 'The template plan must use schema version 4 or later and contain city cells.'
}

$gridWidth = 1 + [int](($cells | Measure-Object -Property x -Maximum).Maximum)
$gridHeight = 1 + [int](($cells | Measure-Object -Property y -Maximum).Maximum)
if ($gridWidth -lt 1 -or $gridHeight -lt 1 -or $cells.Count -ne ($gridWidth * $gridHeight)) {
    throw 'The template plan does not contain a complete rectangular city grid.'
}

$tileSize = [int][Math]::Floor(4096 / [Math]::Max($gridWidth, $gridHeight))
if ($tileSize -lt 1) {
    throw "The $gridWidth by $gridHeight city grid exceeds the 4096px wireframe material limit."
}
$cellHalfExtent = 1640.0

if (-not (Test-Path -LiteralPath $NavmeshDirectory -PathType Container)) {
    throw "The runtime navmesh directory does not exist: $NavmeshDirectory"
}

if ($WhatIf) {
    Write-Output "WhatIf: parse Source navmesh version $navVersion files from $NavmeshDirectory and render $($cells.Count) cell wireframes into $($gridWidth * $tileSize)x$($gridHeight * $tileSize): $OutputPath"
    return
}

$navmeshesByMap = @{}
$invalidNavmeshes = @{}
foreach ($mapName in @($cells | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension([string]$_.cellTemplateFilename) } | Sort-Object -Unique)) {
    $navmeshPath = Join-Path $NavmeshDirectory "$mapName.nav"
    if (-not (Test-Path -LiteralPath $navmeshPath -PathType Leaf)) {
        continue
    }
    try {
        $navmeshesByMap[$mapName] = [ZombieSimNavmeshReader]::ReadAreas($navmeshPath)
    } catch {
        $invalidNavmeshes[$mapName] = $_.Exception.Message
    }
}

Add-Type -AssemblyName System.Drawing
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
$bitmap = [System.Drawing.Bitmap]::new([int]($gridWidth * $tileSize), [int]($gridHeight * $tileSize))
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$availableCells = 0
$unavailableCells = 0
try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(255, 9, 14, 18))
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $wirePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 74, 224, 190), [Math]::Max(1, $tileSize / 96))
    $missingBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 39, 32, 35))
    try {
        foreach ($cell in $cells) {
            $mapName = [System.IO.Path]::GetFileNameWithoutExtension([string]$cell.cellTemplateFilename)
            $destinationX = [int]$cell.x * $tileSize
            $destinationY = [int]$cell.y * $tileSize
            if (-not $navmeshesByMap.ContainsKey($mapName)) {
                $graphics.FillRectangle($missingBrush, $destinationX, $destinationY, $tileSize, $tileSize)
                $unavailableCells++
                continue
            }

            foreach ($area in @($navmeshesByMap[$mapName])) {
                $points = [System.Drawing.PointF[]]@(
                    [System.Drawing.PointF]::new([single]($destinationX + (($area.NorthWestX + $cellHalfExtent) / (2 * $cellHalfExtent)) * $tileSize), [single]($destinationY + (($cellHalfExtent - $area.NorthWestY) / (2 * $cellHalfExtent)) * $tileSize)),
                    [System.Drawing.PointF]::new([single]($destinationX + (($area.SouthEastX + $cellHalfExtent) / (2 * $cellHalfExtent)) * $tileSize), [single]($destinationY + (($cellHalfExtent - $area.NorthWestY) / (2 * $cellHalfExtent)) * $tileSize)),
                    [System.Drawing.PointF]::new([single]($destinationX + (($area.SouthEastX + $cellHalfExtent) / (2 * $cellHalfExtent)) * $tileSize), [single]($destinationY + (($cellHalfExtent - $area.SouthEastY) / (2 * $cellHalfExtent)) * $tileSize)),
                    [System.Drawing.PointF]::new([single]($destinationX + (($area.NorthWestX + $cellHalfExtent) / (2 * $cellHalfExtent)) * $tileSize), [single]($destinationY + (($cellHalfExtent - $area.SouthEastY) / (2 * $cellHalfExtent)) * $tileSize))
                )
                $graphics.DrawPolygon($wirePen, $points)
            }
            $availableCells++
        }
    } finally {
        $wirePen.Dispose()
        $missingBrush.Dispose()
    }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

Write-Output "Rendered $availableCells navmesh wireframes from $($navmeshesByMap.Count) files; $unavailableCells unavailable cells; $($invalidNavmeshes.Count) invalid files: $OutputPath"
