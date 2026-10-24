Include %occStatus

/// One-off, resumable migration of legacy <code>^ZPM.PackageS</code> stream bytes to host files.
/// <p><method>Copy</method> works on raw storage (any compiled property types): for every
/// ZPM.Package row whose package/manifest/installer slot still holds a global stream id, it copies
/// the bytes unchanged to <class>ZPM.PackageStorage</class> paths and verifies SHA-1 equality. An
/// existing file is never overwritten; a differing one is reported as a mismatch.
/// <p><method>Repoint</method> (needs the file-stream property types) re-saves each row with its
/// stream properties linked to those files and verifies the archive hash did not change.
/// <p><method>Check</method> counts rows still referencing <code>^ZPM.PackageS</code> and rows whose
/// archive bytes are not on disk. Every row result is appended to
/// <code>&lt;package-files-root&gt;/migrate-streams.log</code>.
Class ZPM.StreamMigration
{

Parameter EMPTYSHA1 = "da39a3ee5e6b4b0d3255bfef95601890afd80709";

/// Storage slots in ^ZPM.PackageD(name,channel,version) and their file names.
ClassMethod Slots(Output slots)
{
    Set slots(8) = $ListBuild("package", ##class(ZPM.PackageStorage).#ARCHIVENAME, "%Stream.GlobalBinary")
    Set slots(10) = $ListBuild("manifest", ##class(ZPM.PackageStorage).#MANIFESTNAME, "%Stream.GlobalCharacter")
    Set slots(12) = $ListBuild("installer", ##class(ZPM.PackageStorage).#INSTALLERNAME, "%Stream.GlobalCharacter")
}

/// Global stream id held in a raw slot value, or "" when the value is empty or a file reference.
ClassMethod GlobalId(value As %String) As %String
{
    If value = "" Return ""
    If $ListValid(value) && ($ListLength(value) > 1) {
        Return $Select($ListGet(value, 2) [ "Global":$ListGet(value, 1), 1:"")
    }
    Return $Select(value?1.N:value, 1:"")
}

/// Size of the legacy global stream a raw slot value points at (0 when none or emptied).
ClassMethod GlobalBytes(value As %String, cls As %String) As %Integer
{
    Set gid = ..GlobalId(value)
    Return:gid="" 0
    Set src = $ClassMethod(cls, "%Open", $ListBuild(gid, cls, "^ZPM.PackageS"))
    Return $Select($IsObject(src):+src.Size, 1:0)
}

/// SHA-1 of a file: raw bytes, or the decoded characters for UTF-8 text sidecars.
ClassMethod FileHash(path As %String, isChar As %Boolean) As %String
{
    If 'isChar Return $$$lcase(##class(%File).SHA1Hash(path, 1))
    Set fc = ##class(ZPM.PackageStorage).OpenDiskCharacter(path)
    Return:'$IsObject(fc) ""
    Return ..Hex($System.Encryption.SHA1HashStream(fc))
}

ClassMethod Hex(raw As %String) As %String
{
    Set str = ""
    For i=1:1:$Length(raw) Set str = str _ $Translate($Justify($ZHex($Ascii(raw, i)), 2), " ", 0)
    Return $$$lcase(str)
}

ClassMethod Log(line As %String)
{
    Set path = ##class(%File).NormalizeFilename("migrate-streams.log", ##class(ZPM.Settings).GetPackageFilesRoot())
    Set f = ##class(%File).%New(path)
    If $$$ISOK(f.Open("WAS")) {
        Do f.WriteLine($ZDateTime($Horolog, 3) _ " " _ line)
        Do f.Close()
    }
}

/// Copy global stream bytes to disk. <var>batch</var> caps rows copied per call (0 = all).
ClassMethod Copy(dryRun As %Boolean = 1, batch As %Integer = 0, Output report As %DynamicObject) As %Status
{
    Do ..Slots(.slots)
    Set report = {"dryRun":(''dryRun), "rows":0, "copied":0, "alreadyOnDisk":0, "emptyGlobal":0, "mismatch":0, "errors":0, "remaining":0}
    Set sc = $$$OK, q = "^ZPM.PackageD", done = 0
    For {
        Set q = $Query(@q)
        Quit:q=""
        Continue:$QLength(q)'=3
        Set name = $QSubscript(q, 1), ch = $QSubscript(q, 2), ver = $QSubscript(q, 3), d = @q
        Set report.rows = report.rows + 1
        Set rowCopied = 0
        Set slot = ""
        For {
            Set slot = $Order(slots(slot))
            Quit:slot=""
            Set gid = ..GlobalId($ListGet(d, slot))
            Continue:gid=""
            If (batch > 0) && (done >= batch) { Set report.remaining = report.remaining + 1 Quit }
            Set prop = $ListGet(slots(slot), 1), cls = $ListGet(slots(slot), 3)
            Set tag = name _ "@" _ ch _ "@" _ ver _ " " _ prop
            Try {
                Set src = $ClassMethod(cls, "%Open", $ListBuild(gid, cls, "^ZPM.PackageS"))
                If '$IsObject(src) $$$ThrowStatus($$$ERROR($$$GeneralError, "global stream "_gid_" not found"))
                If src.Size = 0 {
                    // Dangling reference to an emptied stream: nothing to copy; Repoint drops it.
                    Set report.emptyGlobal = report.emptyGlobal + 1
                    Do ..Log("COPY empty-global " _ tag _ " id=" _ gid)
                    Quit
                }
                Set srcHash = ..Hex($System.Encryption.SHA1HashStream(src))
                Set isChar = (cls [ "Character")
                Set path = ##class(%File).NormalizeFilename($ListGet(slots(slot), 2), ##class(ZPM.PackageStorage).VersionDirectory(name, ch, ver))
                If ##class(%File).Exists(path) {
                    Set fileHash = ..FileHash(path, isChar)
                    If fileHash = srcHash {
                        Set report.alreadyOnDisk = report.alreadyOnDisk + 1
                        Do ..Log("COPY ok-existing " _ tag _ " sha1=" _ srcHash)
                    } Else {
                        Set report.mismatch = report.mismatch + 1
                        Set sc = $$$ADDSC(sc, $$$ERROR($$$GeneralError, "disk/global mismatch: "_tag))
                        Do ..Log("COPY MISMATCH " _ tag _ " global=" _ srcHash _ " disk=" _ fileHash)
                    }
                    Quit
                }
                If dryRun {
                    Do ..Log("COPY would-copy " _ tag _ " bytes=" _ src.Size)
                    Set report.copied = report.copied + 1, rowCopied = 1
                    Quit
                }
                Set err = ""
                If '##class(ZPM.PackageStorage).EnsureVersionDirectory(name, ch, ver, .err) $$$ThrowStatus($$$ERROR($$$GeneralError, err))
                If isChar {
                    // Text sidecars are read back as UTF-8 (PackageStorage.OpenDiskCharacter).
                    $$$ThrowOnError(##class(ZPM.PackageStorage).CopyStreamToCharacterFile(src, path, "UTF8", .err))
                    Set bytes = ##class(%File).GetFileSize(path)
                } Else {
                    $$$ThrowOnError(##class(ZPM.PackageStorage).CopyStreamToFile(src, path, .bytes, .err))
                }
                Set fileHash = ..FileHash(path, isChar)
                If fileHash '= srcHash {
                    Do ##class(%File).Delete(path)
                    $$$ThrowStatus($$$ERROR($$$GeneralError, "hash changed during copy"))
                }
                Set report.copied = report.copied + 1, rowCopied = 1
                Do ..Log("COPY copied " _ tag _ " bytes=" _ bytes _ " sha1=" _ srcHash)
            } Catch ex {
                Set report.errors = report.errors + 1
                Set sc = $$$ADDSC(sc, ex.AsStatus())
                Do ..Log("COPY ERROR " _ tag _ " " _ ex.DisplayString())
            }
        }
        Set:rowCopied done = done + 1
    }
    Return sc
}

/// Link every row's stream properties to its on-disk files and re-save it.
/// Rows already pointing at files (or with nothing on disk and nothing in globals) are skipped.
ClassMethod Repoint(dryRun As %Boolean = 1, batch As %Integer = 0, Output report As %DynamicObject) As %Status
{
    Do ..Slots(.slots)
    Set report = {"dryRun":(''dryRun), "rows":0, "repointed":0, "skipped":0, "errors":0, "remaining":0}
    Set prop = ##class(%Dictionary.CompiledProperty).%OpenId("ZPM.Package||manifest")
    If '$IsObject(prop) || (prop.Type '= "%Stream.FileCharacter") {
        Return $$$ERROR($$$GeneralError, "ZPM.Package stream properties are not file streams yet; load the new code first")
    }
    Set sc = $$$OK, q = "^ZPM.PackageD", done = 0
    For {
        Set q = $Query(@q)
        Quit:q=""
        Continue:$QLength(q)'=3
        Set name = $QSubscript(q, 1), ch = $QSubscript(q, 2), ver = $QSubscript(q, 3), d = @q
        Set report.rows = report.rows + 1
        Set needs = 0, slot = ""
        For {
            Set slot = $Order(slots(slot))
            Quit:slot=""
            Set path = ##class(%File).NormalizeFilename($ListGet(slots(slot), 2), ##class(ZPM.PackageStorage).VersionDirectory(name, ch, ver))
            Set v = $ListGet(d, slot)
            If ..GlobalId(v) '= "" Set needs = 1
            If ##class(%File).Exists(path) && ($$$lcase(##class(%File).NormalizeFilename(v)) '= $$$lcase(path)) Set needs = 1
        }
        If 'needs { Set report.skipped = report.skipped + 1 Continue }
        If (batch > 0) && (done >= batch) { Set report.remaining = report.remaining + 1 Continue }
        Set tag = name _ "@" _ ch _ "@" _ ver
        If dryRun { Set report.repointed = report.repointed + 1, done = done + 1 Do ..Log("REPOINT would " _ tag) Continue }
        Try {
            Set oldHash = $ListGet(d, 9)
            Set p = ##class(ZPM.Package).NameChannelVersionOpen(name, ch, ver, 4, .tSC)
            $$$ThrowOnError(tSC)
            Set slot = ""
            For {
                Set slot = $Order(slots(slot))
                Quit:slot=""
                Set propName = $ListGet(slots(slot), 1)
                Set path = ##class(%File).NormalizeFilename($ListGet(slots(slot), 2), ##class(ZPM.PackageStorage).VersionDirectory(name, ch, ver))
                If ##class(%File).Exists(path) {
                    If propName = "package" {
                        Set fs = ##class(%Stream.FileBinary).%New()
                        $$$ThrowOnError(fs.LinkToFile(path))
                    } Else {
                        Set fs = ##class(ZPM.PackageStorage).OpenDiskCharacter(path)
                    }
                    Set $Property(p, propName) = fs
                } ElseIf ..GlobalBytes($ListGet(d, slot), $ListGet(slots(slot), 3)) > 0 {
                    $$$ThrowStatus($$$ERROR($$$GeneralError, propName_" still only in ^ZPM.PackageS; run Copy first"))
                } Else {
                    Set $Property(p, propName) = ""
                }
            }
            $$$ThrowOnError(p.%Save())
            Kill p
            Set newHash = $ListGet($Get(^ZPM.PackageD(name, ch, ver)), 9)
            Set archive = ##class(ZPM.PackageStorage).ArchivePath(name, ch, ver)
            Set diskHash = $Select(##class(%File).Exists(archive):$$$lcase(##class(%File).SHA1Hash(archive, 1)), 1:"")
            If (diskHash '= "") && (newHash '= diskHash) $$$ThrowStatus($$$ERROR($$$GeneralError, "row hash "_newHash_" does not match disk "_diskHash))
            // "" and SHA-1("") mean no recorded digest (legacy rows); anything else must be unchanged.
            Set stale = (oldHash = "") || (oldHash = ..#EMPTYSHA1)
            If 'stale && (oldHash '= newHash) $$$ThrowStatus($$$ERROR($$$GeneralError, "hash changed "_oldHash_" -> "_newHash))
            Set report.repointed = report.repointed + 1, done = done + 1
            Do ..Log("REPOINT ok " _ tag _ " hash=" _ newHash _ $Select(stale&&(oldHash'=newHash):" (was "_$Select(oldHash="":"empty",1:"sha1-of-empty")_")", 1:""))
        } Catch ex {
            Set report.errors = report.errors + 1
            Set sc = $$$ADDSC(sc, ex.AsStatus())
            Do ..Log("REPOINT ERROR " _ tag _ " " _ ex.DisplayString())
        }
    }
    Return sc
}

/// Read-only: rows still referencing ^ZPM.PackageS, and rows whose archive bytes are not on disk
/// (rows with no archive anywhere, e.g. uplink metadata, are counted separately).
ClassMethod Check(Output report As %DynamicObject) As %Status
{
    Do ..Slots(.slots)
    Set report = {"rows":0, "globalRefs":0, "archiveOnDisk":0, "noArchiveAnywhere":0, "manifestOnDisk":0, "installerOnDisk":0, "installerRows":0, "globalRefRows":[]}
    Set q = "^ZPM.PackageD"
    For {
        Set q = $Query(@q)
        Quit:q=""
        Continue:$QLength(q)'=3
        Set name = $QSubscript(q, 1), ch = $QSubscript(q, 2), ver = $QSubscript(q, 3), d = @q
        Set report.rows = report.rows + 1
        Set ref = 0, slot = ""
        For {
            Set slot = $Order(slots(slot))
            Quit:slot=""
            Set:..GlobalId($ListGet(d, slot))'="" ref = 1
        }
        If ref {
            Set report.globalRefs = report.globalRefs + 1
            Do:report.globalRefRows.%Size()<20 report.globalRefRows.%Push(name_"@"_ch_"@"_ver)
        }
        If ##class(ZPM.PackageStorage).DiskArchiveExists(name, ch, ver) {
            Set report.archiveOnDisk = report.archiveOnDisk + 1
        } ElseIf ($ListGet(d, 8) = "") {
            Set report.noArchiveAnywhere = report.noArchiveAnywhere + 1
        }
        Set:##class(%File).Exists(##class(ZPM.PackageStorage).ManifestPath(name, ch, ver)) report.manifestOnDisk = report.manifestOnDisk + 1
        If $ListGet(d, 12) '= "" {
            Set report.installerRows = report.installerRows + 1
            Set:##class(%File).Exists(##class(ZPM.PackageStorage).InstallerPath(name, ch, ver)) report.installerOnDisk = report.installerOnDisk + 1
        }
    }
    Return $$$OK
}

}
