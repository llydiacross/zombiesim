Set-StrictMode -Version Latest

# Read-only access to mounted Valve VPK archives so build tools can inspect VMT/VTF headers in place.
# Nothing is extracted to disk; callers must reference the mounted virtual path, never copy Valve content.
if (-not ('ZombieSim.VpkArchive' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace ZombieSim {
    public sealed class VpkArchive {
        struct Entry { public ushort Archive; public uint Offset; public uint Length; public byte[] Preload; }
        readonly Dictionary<string, Entry> entries = new Dictionary<string, Entry>(StringComparer.OrdinalIgnoreCase);
        readonly string directoryPath;
        readonly string archivePrefix;
        uint dataOffset;

        public VpkArchive(string path) {
            directoryPath = path;
            archivePrefix = path.Substring(0, path.Length - "_dir.vpk".Length);
            using (var reader = new BinaryReader(File.OpenRead(path))) {
                if (reader.ReadUInt32() != 0x55aa1234) throw new InvalidDataException("Not a VPK directory: " + path);
                uint version = reader.ReadUInt32();
                uint treeSize = reader.ReadUInt32();
                if (version == 2) reader.ReadBytes(16);
                else if (version != 1) throw new InvalidDataException("Unsupported VPK version " + version + ": " + path);
                uint headerSize = (uint)reader.BaseStream.Position;
                dataOffset = headerSize + treeSize;
                while (true) {
                    string extension = ReadString(reader);
                    if (extension.Length == 0) break;
                    while (true) {
                        string directory = ReadString(reader);
                        if (directory.Length == 0) break;
                        while (true) {
                            string name = ReadString(reader);
                            if (name.Length == 0) break;
                            reader.ReadUInt32();
                            ushort preloadBytes = reader.ReadUInt16();
                            var entry = new Entry();
                            entry.Archive = reader.ReadUInt16();
                            entry.Offset = reader.ReadUInt32();
                            entry.Length = reader.ReadUInt32();
                            reader.ReadUInt16();
                            entry.Preload = preloadBytes > 0 ? reader.ReadBytes(preloadBytes) : new byte[0];
                            string fullPath = (directory == " " ? "" : directory + "/") + name + (extension == " " ? "" : "." + extension);
                            entries[fullPath] = entry;
                        }
                    }
                }
            }
        }

        static string ReadString(BinaryReader reader) {
            var bytes = new List<byte>();
            byte value;
            while ((value = reader.ReadByte()) != 0) bytes.Add(value);
            return Encoding.UTF8.GetString(bytes.ToArray());
        }

        public string Path { get { return directoryPath; } }
        public int Count { get { return entries.Count; } }
        public bool Contains(string path) { return entries.ContainsKey(Normalize(path)); }

        public byte[] ReadFile(string path, int maxBytes) {
            Entry entry;
            if (!entries.TryGetValue(Normalize(path), out entry)) return null;
            int total = entry.Preload.Length + (int)entry.Length;
            int wanted = maxBytes > 0 ? Math.Min(maxBytes, total) : total;
            var result = new byte[wanted];
            int copied = Math.Min(entry.Preload.Length, wanted);
            Array.Copy(entry.Preload, result, copied);
            if (copied < wanted) {
                string archivePath = entry.Archive == 0x7fff ? directoryPath : archivePrefix + "_" + entry.Archive.ToString("000") + ".vpk";
                long offset = entry.Archive == 0x7fff ? dataOffset + entry.Offset : entry.Offset;
                using (var stream = File.OpenRead(archivePath)) {
                    stream.Seek(offset, SeekOrigin.Begin);
                    int read = 0;
                    while (copied + read < wanted) {
                        int n = stream.Read(result, copied + read, wanted - copied - read);
                        if (n <= 0) break;
                        read += n;
                    }
                }
            }
            return result;
        }

        static string Normalize(string path) { return path.Replace('\\', '/').TrimStart('/').ToLowerInvariant(); }
    }
}
'@
}

function New-VpkSearchPath {
    param(
        [string[]]$LooseDirectories = @(),
        [string[]]$VpkPaths = @()
    )

    $archives = [System.Collections.Generic.List[object]]::new()
    foreach ($vpkPath in $VpkPaths) {
        if (Test-Path -LiteralPath $vpkPath -PathType Leaf) {
            $archives.Add([ZombieSim.VpkArchive]::new((Resolve-Path -LiteralPath $vpkPath).Path))
        }
    }
    return [pscustomobject]@{
        LooseDirectories = @($LooseDirectories | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
        Archives = $archives
    }
}

function Read-VpkSearchPathFile {
    param(
        [Parameter(Mandatory)] $SearchPath,
        [Parameter(Mandatory)] [string]$VirtualPath,
        [int]$MaxBytes = 0
    )

    $normalized = $VirtualPath.Replace('\', '/').TrimStart('/').ToLowerInvariant()
    foreach ($directory in $SearchPath.LooseDirectories) {
        $candidate = Join-Path $directory $normalized.Replace('/', '\')
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($candidate)
            if ($MaxBytes -gt 0 -and $bytes.Length -gt $MaxBytes) { $bytes = $bytes[0..($MaxBytes - 1)] }
            return [pscustomobject]@{ Source = $candidate; Bytes = [byte[]]$bytes }
        }
    }
    foreach ($archive in $SearchPath.Archives) {
        $bytes = $archive.ReadFile($normalized, $MaxBytes)
        if ($null -ne $bytes) {
            return [pscustomobject]@{ Source = "$($archive.Path)::$normalized"; Bytes = $bytes }
        }
    }
    return $null
}

Export-ModuleMember -Function New-VpkSearchPath, Read-VpkSearchPathFile
