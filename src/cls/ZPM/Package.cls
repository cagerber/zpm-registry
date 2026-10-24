Class ZPM.Package Extends (%Persistent, %JSON.Adaptor)
{

Parameter EXTENTQUERYSPEC = "name,channel,version";

Parameter %JSONIGNOREINVALIDFIELD As BOOLEAN = 1;

/// The release channel this artefact was published into.
/// 
/// ONE registry hosts every channel, so the channel is part of the package identity:
/// the same module@version may legitimately exist in `develop` and in `sprint` without
/// either shadowing the other, and a lookup that does not name a channel is ambiguous.
/// Decided by the estate-release programme (D3): a channel is a feed, and it is NOT
/// encoded in the module name or the version.
Property channel As %String(MAXLEN = 20) [ Required ];

Index Channel On channel;

Property name As %String(MAXLEN = 50) [ Required ];

Index Name On name;

Property version As %String [ Required ];

Index NameChannelVersion On (name, channel, version) [ IdKey, Unique ];

Property owner As %String(%JSONINCLUDE = "NONE");

Index Owner On owner;

Property description As %String(MAXLEN = 1000, TRUNCATE = 1);

Property keywords As list Of %String;

Property license As %String;

Property homePage As %String;

Property repository As %String(MAXLEN = 200);

Index Repository On repository;

Property dependencies As array Of %String;

/// Archive bytes live only in a host file (see ZPM.PackageStorage); never in ^ZPM.PackageS.
Property package As %Stream.FileBinary(%JSONINCLUDE = "NONE");

Property size As %Integer(%JSONINCLUDE = "OUTPUTONLY");

Property manifest As %Stream.FileCharacter(%JSONINCLUDE = "INPUTONLY");

Property installer As %Stream.FileCharacter(%JSONINCLUDE = "INPUTONLY");

Property hash As %String(%JSONINCLUDE = "OUTPUTONLY") [ SqlComputeCode = { Set {*} = ..GetPackageHash({package})}, SqlComputed, SqlComputeOnChange = %%UPDATE ];

Property url As %String(%JSONINCLUDE = "OUTPUTONLY", MAXLEN = 200) [ Transient ];

Property installerUrl As %String(%JSONFIELDNAME = "installer", %JSONINCLUDE = "OUTPUTONLY", MAXLEN = 200) [ Transient ];

Property versions As list Of %String(%JSONINCLUDE = "OUTPUTONLY", MAXLEN = 200) [ Transient ];

Property platformVersions As list Of %String(%JSONFIELDNAME = "platform_versions", %JSONINCLUDE = "OUTPUTONLY", MAXLEN = 10) [ Transient ];

Property versionMajor As %Integer(%JSONINCLUDE = "NONE") [ SqlComputeCode = {Set {*} = +$Piece({version},".",1)}, SqlComputed, SqlComputeOnChange = %%INSERT ];

Property versionMinor As %Integer(%JSONINCLUDE = "NONE") [ SqlComputeCode = {Set {*} = +$Piece({version},".",2)}, SqlComputed, SqlComputeOnChange = %%INSERT ];

Property versionPatch As %Integer(%JSONINCLUDE = "NONE") [ SqlComputeCode = {Set {*} = +$Piece($Piece($Piece({version},".",3),"-"),"+")}, SqlComputed, SqlComputeOnChange = %%INSERT ];

Property versionPrerelease As %String(%JSONINCLUDE = "NONE") [ SqlComputeCode = {Set {*} = $Piece($Piece($Piece({version},".",3,*),"-",2,*),"+")}, SqlComputed, SqlComputeOnChange = %%INSERT ];

Property versionBuildmetadata As %String(%JSONINCLUDE = "NONE") [ SqlComputeCode = {Set {*} = $Piece({version},"+",2)}, SqlComputed, SqlComputeOnChange = %%INSERT ];

Property publishTS As %PosixTime [ SqlComputeCode = {Set {*} = ##class(%Library.PosixTime).CurrentUTCTimeStamp()}, SqlComputed, SqlComputeOnChange = %%INSERT ];

Property UpLink As ZPM.UpLink(%JSONINCLUDE = "NONE");

ForeignKey UpLinkFK(UpLink) References ZPM.UpLink() [ OnDelete = cascade ];

Index NameUpLink On (name, UpLink);

Property deployed As %Boolean;

Property deleted As %Boolean [ InitialExpression = 0 ];

Method nameSet(value As %String) As %Status
{
  Set i%name = $$$lcase(value)
  Quit $$$OK
}

Method sizeGet() As %Integer
{
  Set stream = ..GetPackageStream()
  Return:'$IsObject(stream) ""
  Return:'stream.Size ""
  Return stream.Size
}

/// Package archive for download/hash: on-disk file when present, else legacy ^ZPM.PackageS stream.
Method GetPackageStream() As %Stream.Object
{
  If ##class(ZPM.PackageStorage).DiskArchiveExists(..name, ..channel, ..version) {
    Return ##class(ZPM.PackageStorage).OpenDiskArchive(..name, ..channel, ..version)
  }
  If $IsObject(..package) {
    Do ..package.Rewind()
    If ..package.Size {
      Return ..package
    }
  }
  Return ""
}

Method GetManifestStream() As %Stream.Object
{
  Set path = ##class(ZPM.PackageStorage).ManifestPath(..name, ..channel, ..version)
  If ##class(%File).Exists(path) {
    Return ##class(ZPM.PackageStorage).OpenDiskCharacter(path)
  }
  If $IsObject(..manifest) {
    Do ..manifest.Rewind()
    If ..manifest.Size {
      Return ..manifest
    }
  }
  Return ""
}

Method GetInstallerStream() As %Stream.Object
{
  Set path = ##class(ZPM.PackageStorage).InstallerPath(..name, ..channel, ..version)
  If ##class(%File).Exists(path) {
    Return ##class(ZPM.PackageStorage).OpenDiskCharacter(path)
  }
  If $IsObject(..installer) {
    Do ..installer.Rewind()
    If ..installer.Size {
      Return ..installer
    }
  }
  Return ""
}

Method PersistStreamsToDisk() As %Status
{
  Set errMsg = ""
  If '##class(ZPM.PackageStorage).EnsureVersionDirectory(..name, ..channel, ..version, .errMsg) {
    Return $$$ERROR($$$GeneralError, errMsg)
  }
  If $IsObject(..package) && ..package.Size {
    Set path = ##class(ZPM.PackageStorage).ArchivePath(..name, ..channel, ..version)
    Set sc = ..InstallStreamPropertyToFile(..package, path, .errMsg)
    If $$$ISERR(sc) Return sc
    Set fb = ##class(%Stream.FileBinary).%New()
    Set sc = fb.LinkToFile(path)
    If $$$ISERR(sc) Return sc
    Set ..package = fb
  }
  If $IsObject(..manifest) && ..manifest.Size {
    Set path = ##class(ZPM.PackageStorage).ManifestPath(..name, ..channel, ..version)
    Set sc = ..InstallStreamPropertyToFile(..manifest, path, .errMsg)
    If $$$ISERR(sc) Return sc
    Set fc = ##class(ZPM.PackageStorage).OpenDiskCharacter(path)
    If $IsObject(fc) Set ..manifest = fc
  }
  If $IsObject(..installer) && ..installer.Size {
    Set path = ##class(ZPM.PackageStorage).InstallerPath(..name, ..channel, ..version)
    Set sc = ..InstallStreamPropertyToFile(..installer, path, .errMsg)
    If $$$ISERR(sc) Return sc
    Set fc = ##class(ZPM.PackageStorage).OpenDiskCharacter(path)
    If $IsObject(fc) Set ..installer = fc
  }
  Return $$$OK
}

/// Prefer a host file copy when the stream is already backed by a file; otherwise copy stream bytes unchanged.
Method InstallStreamPropertyToFile(stream As %Stream.Object, destPath As %String, Output errMsg As %String) As %Status [ Private ]
{
  Set errMsg = ""
  Set destPath = ##class(%File).NormalizeFilename(destPath)
  If stream.%IsA("%Stream.FileBinary") {
    Set src = ##class(%File).NormalizeFilename(stream.Filename)
    If (src = destPath) && ##class(%File).Exists(destPath) {
      Return $$$OK
    }
    If ##class(%File).Exists(src) {
      Return ##class(ZPM.PackageStorage).InstallFileFromPath(src, destPath, .errMsg)
    }
  }
  If stream.%IsA("%Stream.FileCharacter") && (stream.Filename '= "") {
    Set src = ##class(%File).NormalizeFilename(stream.Filename)
    If (src = destPath) && ##class(%File).Exists(destPath) {
      Return $$$OK
    }
  }
  If stream.%IsA("%Stream.FileCharacter") || stream.%IsA("%Stream.GlobalCharacter") || stream.%IsA("%Stream.TmpCharacter") {
    // Text sidecars are stored as UTF-8 so OpenDiskCharacter reads back the same characters,
    // whatever translate table the incoming temp stream used.
    Return ##class(ZPM.PackageStorage).CopyStreamToCharacterFile(stream, destPath, "UTF8", .errMsg)
  }
  Set bytes = 0
  Return ##class(ZPM.PackageStorage).CopyStreamToFile(stream, destPath, .bytes, .errMsg)
}

Method %OnBeforeSave(insert As %Boolean) As %Status
{
  If (..name = "") || (..channel = "") || (..version = "") {
    Return $$$OK
  }
  Return ..PersistStreamsToDisk()
}

Method packageFromBase64(base64 As %Stream.DynamicBinary) As %Status
{
  If (..name = "") || (..channel = "") || (..version = "") {
    Return $$$ERROR($$$GeneralError, "name, channel and version required before package payload")
  }
  Set errMsg = ""
  If '##class(ZPM.PackageStorage).EnsureVersionDirectory(..name, ..channel, ..version, .errMsg) {
    Return $$$ERROR($$$GeneralError, errMsg)
  }
  Set path = ##class(ZPM.PackageStorage).ArchivePath(..name, ..channel, ..version)
  Set tmpPath = path _ ".writing"
  If ##class(%File).Exists(tmpPath) {
    Do ##class(%File).Delete(tmpPath)
  }
  Set sc = $$$OK
  Set out = ##class(%Stream.FileBinary).%New()
  Set sc = out.LinkToFile(tmpPath)
  If $$$ISERR(sc) Return sc
  Do base64.Rewind()
  While 'base64.AtEnd {
    Set tSC = out.Write($System.Encryption.Base64Decode(base64.Read(43540, .sc)))
    Set:$$$ISERR(tSC) sc = $$$ADDSC(sc, tSC)
  }
  If $$$ISERR(sc) {
    Do ##class(%File).Delete(tmpPath)
    Return sc
  }
  Set sc = out.%Save()
  If $$$ISERR(sc) {
    Do ##class(%File).Delete(tmpPath)
    Return sc
  }
  // Close the handle first: Windows refuses to rename an open file.
  Kill out
  If ##class(%File).Exists(path) {
    Do ##class(%File).Delete(path)
  }
  If '##class(%File).Rename(tmpPath, path) {
    Do ##class(%File).Delete(tmpPath)
    Return $$$ERROR($$$GeneralError, "unable to finalize package archive")
  }
  Set fb = ##class(%Stream.FileBinary).%New()
  Set sc = fb.LinkToFile(path)
  If $$$ISERR(sc) Return sc
  Set ..package = fb
  Set ..hash = $$$lcase(##class(%File).SHA1Hash(path, 1))
  Return $$$OK
}

Method filepathGet() As %String [ CodeMode = expression ]
{
..name _ "/-"
}

Method filenameGet() As %String [ CodeMode = expression ]
{
..name _ "-" _ ..version
}

ClassMethod GetPackageHash(pStream As %Stream.Object) As %String
{
  If (pStream="") { Return "" }
  If '$IsObject(pStream) { Set pStream = ..packageOpen(pStream) }
  Set hash = $System.Encryption.SHA1HashStream(pStream)
  Set str="" 
  For i=1:1:$Length(hash) {
		Set str=str_$Translate($Justify($ZHex($Ascii(hash, i)),2)," ",0)
	}
  Return $$$lcase(str)
}

Method urlGet() As %String
{
  Quit:'..size ""
  Set host = ##class(ZPM.Utils).ServerURL()
  Return host _ "/download/" _ $ZConvert(..filepathGet() _ "/" _ ..filenameGet() _ ".tgz", "O", "URL")
}

Method installerUrlGet() As %String
{
  If ('..installer.Size) {
    Return ""
  }
  Set host =  ##class(ZPM.Utils).ServerURL()
  Set name = $ZConvert(..name, "O", "URL")
  Set version = $ZConvert(..version, "O", "URL")
  Return host _ "/packages/" _ name _ "/" _ version _ "/installer"
}

Method versionsGet() As %ListOfDataTypes
{
  Set tList = ##class(%ListOfDataTypes).%New()

  Set name = ..name
  Set tPrerelease = $Select($Data(%request) # 2: %request.Get("includePrerelease", 1), 1: 1)
  Set tSnapshot = $Select($Data(%request) # 2: %request.Get("includeSnapshots", 1), 1: 1)
  &sql(
    SELECT %DLIST(version) INTO :versions 
    FROM Package 
    WHERE name = :name
    AND (
      versionPrerelease IS NULL 
      OR (:tSnapshot = 1 AND LOWER(versionPrerelease) = 'snapshot')
      OR (:tPrerelease = 1 AND LOWER(versionPrerelease) <> 'snapshot')
    )
  )
  If (SQLCODE=0) {
    Set ptr = 0
    While $ListNext(versions, ptr, version) {
      Continue:version=""
      Set list(version) = ""
    }
  }

  Set version = ""
  For {
    Set version = $Order(list(version), 1)
    Quit:version=""
    Do tList.Insert(version)
  }
  Return tList
}

ClassMethod VersionFind(pkg As %String = "", version As %String = "", pPrerelease As %Boolean = 1, pSnapshot As %Boolean = 1, channel As %String = "") As %String
{
  // ONE registry hosts every channel, so a lookup that does not name a channel is
  // ambiguous: the same module@version may exist in `develop` and in `sprint`. Refuse
  // rather than guess — a wrong answer here would install another channel's build.
  If (channel = "") { Return "" }
  // Reserved channel for packages MIRRORED from an upstream registry (UpLink proxies).
  // Deliberately not one of the four release channels, so a community mirror can never
  // be mistaken for a release-channel build of the same module@version.
  Set mirrorChannel = "uplink"
  If (version = "") || (version = "latest") || (version = "*") {
    // package was published directly in this registry - return the last version
    &sql(SELECT TOP 1 Version INTO :version FROM ZPM.Package 
        WHERE Name = :pkg 
          AND channel = :channel
          AND UpLink IS NULL
          AND (
            versionPrerelease IS NULL 
            OR (:pSnapshot = 1 AND LOWER(versionPrerelease) = 'snapshot')
            OR (:pPrerelease = 1 AND LOWER(versionPrerelease) <> 'snapshot')
          )
        ORDER BY versionMajor DESC, versionMinor DESC, versionPatch DESC, versionPrerelease DESC, versionBuildmetadata DESC
    )
    If SQLCODE=0 { 
      // found 
      Return version
    } Else {
      // Nothing in the requested channel — fall back to the MIRROR.
      Do ##class(ZPM.UpLink).LoadPackageFromAllUpLinks(pkg, "latest")
      &sql(SELECT TOP 1 Version INTO :version FROM ZPM.Package 
          WHERE Name = :pkg 
            AND channel = :mirrorChannel
            AND (
              versionPrerelease IS NULL 
              OR (:pSnapshot = 1 AND LOWER(versionPrerelease) = 'snapshot')
              OR (:pPrerelease = 1 AND LOWER(versionPrerelease) <> 'snapshot')
            )
          ORDER BY versionMajor DESC, versionMinor DESC, versionPatch DESC, versionPrerelease DESC, versionBuildmetadata DESC
      )
      If SQLCODE=0 { 
        Set package = ##class(ZPM.Package).%OpenId(pkg_"||"_mirrorChannel_"||"_version)
        If ('$IsObject(package)) { Return ""}
        If ($IsObject(package.GetManifestStream()) && package.GetManifestStream().Size) { Return version }
        Do ##class(ZPM.UpLink).LoadPackageFromAllUpLinks(pkg, version)
        Return version
      } 
      Return ""
    }
  } Else {
    // Exact version: the requested channel first, then the mirror.
    If ..%ExistsId(pkg _ "||" _ channel _ "||" _ version) {
      Set package = ##class(ZPM.Package).%OpenId(pkg_"||"_channel_"||"_version)
      If ('$IsObject(package)) { Return ""}
      If ($IsObject(package.GetManifestStream()) && package.GetManifestStream().Size) { Return version }
    } 
    Do ##class(ZPM.UpLink).LoadPackageFromAllUpLinks(pkg, version)
    If ..%ExistsId(pkg _ "||" _ mirrorChannel _ "||" _ version) {
      Return version
    }
    Return ""
  }
}

Trigger DeletePackageTrigger [ Event = DELETE, Foreach = row/object ]
{
  // delete DeployedPackage
  New id,package,name,version
  Set id = {ID}
  Set package = ##class(Package).%OpenId(id)
  Set name = package.name
  Set version = package.version
  &sql(DELETE FROM ZPM.DeployedPackage WHERE name = :name AND version = :version)
}

ClassMethod MarkAsDeleted(name, version, channel) As %Boolean
{
  Set package = ##class(ZPM.Package).NameChannelVersionOpen(name, channel, version, , .tSC)
  If ($ISOBJECT(package) && (package.deleted = 1)) {
    Return 1
  }
  Return 0
}

Method platformVersionsGet() As %ListOfDataTypes
{
  Set tList = ##class(%ListOfDataTypes).%New()

  Set name = ..name
  Set version = ..version
  &sql(SELECT %DLIST(platformVersion) INTO :versions FROM DeployedPackage WHERE name = :name AND version = :version)
  If (SQLCODE=0) {
    Set ptr = 0
    While $ListNext(versions, ptr, version) {
      Continue:version=""
      Set list(version) = ""
    }
  }

  Set version = ""
  For {
    Set version = $Order(list(version), 1)
    Quit:version=""
    Do tList.Insert(version)
  }
  Return tList
}

ClassMethod DeleteExistingPackages(pkg As %String, version As %String, channel As %String) As %Status
{
  // delete all "proxy" packages FOR THIS CHANNEL: proxies are per-channel too, since
  // the same upstream module may be mirrored into several channels.
  &sql(DELETE FROM ZPM.Package WHERE Name = :pkg AND channel = :channel AND UpLink IS NOT NULL)
  Set tSC = ##class(ZPM.PackageStorage).DeleteVersionDirectory(pkg, channel, version)
  Return:$$$ISERR(tSC) tSC
  Set tSC = ..NameChannelVersionDelete(pkg, channel, version)
  Return:$$$ISERR(tSC) tSC

  Return $$$OK
}

ClassMethod DeletePackageVersion(pkg As %String, version As %String, channel As %String) As %Status
{
  Set package = ##class(ZPM.Package).NameChannelVersionOpen(pkg, channel, version, , .tSC)
  Return:$$$ISERR(tSC) tSC
  Set package.deleted = 1
  Set tSC = package.%Save()
  Return:$$$ISERR(tSC) tSC
  Set count = 0
  &sql(SELECT count(1) INTO :count FROM ZPM.Package WHERE name = :pkg AND channel = :channel AND (deleted IS NULL OR deleted != 1))
  If (count = 0) {
    Return ..DeletePackage(pkg, channel)
  }
  Return $$$OK
}

ClassMethod DeletePackage(pkg As %String, channel As %String) As %Status
{
  &sql(DELETE FROM ZPM.Package WHERE name = :pkg AND channel = :channel)
  If SQLCODE'=0 Return $$$ERROR($$$SQLError, SQLCODE, $g(%msg))
  Return $$$OK
}

ClassMethod versionValidate(pkg As %String = "", version As %String = "", channel As %String = "") As %String
{
  If (pkg="") {
    Return ""
  }
  If (channel = "") {
    Return ""
  }
  If (version = "") || (version = "latest") || (version = "*") {
    &sql(SELECT TOP 1 Version INTO :version FROM ZPM.Package WHERE Name = :pkg AND channel = :channel
          ORDER BY versionMajor DESC, versionMinor DESC, versionPatch DESC, versionPrerelease DESC, versionBuildmetadata DESC
    )
    If SQLCODE'=0 Return ""
    Return version
  }
  If ..%ExistsId(pkg _ "||" _ channel _ "||" _ version) {
    Return version
  }
  Return ""
}

ClassMethod Populate(Path As %String, kill = 0, channel As %String = "")
{
  If '##class(%File).DirectoryExists(Path) {
    Return
  }
  
  Do:kill ..%KillExtent()
  
  Set rs = ##class(%File).FileSetFunc(Path)
  While rs.%Next() {
    Set name = rs.name
    Continue:rs.Type'="D"
    
    Set tSC = ..LoadPackage(name, channel)
    If $$$ISERR(tSC) {
      Do $System.OBJ.DisplayError(tSC)
    }
  }
}

Method UpdateDescriptionFromManifest() As %Status
{
  Try {
    Set manifestStream = ..GetManifestStream()
    Return:'$IsObject(manifestStream) $$$OK
    $$$ThrowOnError(##class(%XML.XPATH.Document).CreateFromStream(manifestStream, .tDocument))
    $$$ThrowOnError(tDocument.EvaluateExpression("/Module/Description", "text()", .tRes))
    If (tRes.Count()>0) {
      Set ..description = tRes.GetAt(1).Value
    }
  } Catch ex {
    Do ex.Log()
    Return ex.AsStatus()
  }
  Return $$$OK
}

ClassMethod LoadPackage(Path As %String, channel As %String, repository As %String = "", silent As %Boolean = 0) As %Status
{
  Return $$$ERROR($$$GeneralError, "LoadPackage no longer repackages unpacked directories; use LoadPackageFromArchive with the original .tgz and module.xml")
}

/// Trifour fork (dep-97): ingest a package from the ORIGINAL archive plus its
/// module.xml — no untar and no re-tar.
/// 
/// The stock <method>LoadPackage</method> re-tars an unpacked directory via
/// <code>$zf(-100)</code>. That forces a client-side unpack first, duplicates
/// an archive we already hold, and makes the stored <property>hash</property> a
/// SHA1 of the re-tarred bytes — so it can never identify the uploaded .tgz.
/// This method stores the supplied archive stream as-is, so <property>hash</property>
/// is a genuine digest of the artifact the client produced, and no temporary
/// directory or tar process is needed.
/// 
/// <var>manifestPath</var> is the module.xml that belongs to <var>archivePath</var>
/// (the same file the archive contains), supplied separately so the caller never
/// has to unpack.
/// 
/// @param archivePath IRIS-visible path to the original .tgz
/// @param manifestPath IRIS-visible path to that package's module.xml
/// @param repository Optional repository marker persisted on the record
/// @param silent Suppress progress output
/// @param name Output: lower-cased package name from module.xml
/// @param version Output: package version from module.xml
/// @return %Status
ClassMethod LoadPackageFromArchive(archivePath As %String, manifestPath As %String, channel As %String, repository As %String = "", silent As %Boolean = 0, Output name As %String, Output version As %String) As %Status
{
  If '##class(%File).Exists(archivePath) {
    Return $$$ERROR($$$GeneralError, "archive not found: " _ archivePath)
  }
  If '##class(%File).Exists(manifestPath) {
    Return $$$ERROR($$$GeneralError, "module.xml not found: " _ manifestPath)
  }
  If ('silent) {
    Write !!,"Archive: ", archivePath
    Write !!,"ModuleFile: ", manifestPath
  }
  Set tSC = ##class(%XML.XPATH.Document).CreateFromFile(manifestPath, .tDocument)
  If $$$ISERR(tSC) Return tSC

  Set tSC=tDocument.EvaluateExpression("/Export/Document/Module/Name", "text()", .tRes)
  If $$$ISERR(tSC) Return tSC
  If '$IsObject(tRes.GetAt(1)) {
    Return $$$ERROR($$$GeneralError, "Name required")
  }
  Set name = $$$lcase(tRes.GetAt(1).Value)

  Set tSC=tDocument.EvaluateExpression("/Export/Document/Module/Version", "text()", .tRes)
  If $$$ISERR(tSC) Return tSC
  If '$IsObject(tRes.GetAt(1)) {
    Return $$$ERROR($$$GeneralError, "Version required")
  }
  Set version = tRes.GetAt(1).Value

  Set description = ""
  Set tSC=tDocument.EvaluateExpression("/Export/Document/Module/Description", "text()", .tRes)
  If $$$ISERR(tSC) Return tSC
  If $IsObject(tRes.GetAt(1)) {
    Set description = tRes.GetAt(1).Value
  }

  // Same <Keywords> handling as LoadPackage (Trifour fork, 9-373).
  Set keywords = ""
  Set tSC=tDocument.EvaluateExpression("/Export/Document/Module/Keywords/Keyword", "text()", .tRes)
  If $$$ISERR(tSC) Return tSC
  If tRes.Count() > 0 {
    For i=1:1:tRes.Count() {
      Set kw = $ZStrip(tRes.GetAt(i).Value, "<>W")
      If kw '= "" Set keywords = keywords _ $Select(keywords="":"",1:",") _ kw
    }
  }
  If keywords = "" {
    Set tSC=tDocument.EvaluateExpression("/Export/Document/Module/Keywords", "text()", .tRes)
    If $$$ISERR(tSC) Return tSC
    If $IsObject(tRes.GetAt(1)) Set keywords = tRes.GetAt(1).Value
  }

  If (channel = "") {
    Return $$$ERROR($$$GeneralError, "channel is required: one registry hosts every channel")
  }
  Do ..DeleteExistingPackages(name,version,channel)
  Set errMsg = ""
  If '##class(ZPM.PackageStorage).EnsureVersionDirectory(name, channel, version, .errMsg) {
    Return $$$ERROR($$$GeneralError, errMsg)
  }
  Set archiveDest = ##class(ZPM.PackageStorage).ArchivePath(name, channel, version)
  Set manifestDest = ##class(ZPM.PackageStorage).ManifestPath(name, channel, version)
  Set tSC = ##class(ZPM.PackageStorage).InstallFileFromPath(archivePath, archiveDest, .errMsg)
  If $$$ISERR(tSC) Return tSC
  Set tSC = ##class(ZPM.PackageStorage).InstallFileFromPath(manifestPath, manifestDest, .errMsg)
  If $$$ISERR(tSC) Return tSC
  Set package = ..%New()
  Set package.channel = channel
  Set package.name = name
  Set package.description = description
  Set keywords = $ZStrip(keywords,"<>W")
  If keywords '= "" {
    For i=1:1:$Length(keywords,",") {
      Set kw = $ZStrip($Piece(keywords,",",i),"<>W")
      If kw '= "" Do package.keywords.Insert(kw)
    }
  }
  Set package.repository = repository
  Set package.version = version
  Set archive = ##class(%Stream.FileBinary).%New()
  Set sc = archive.LinkToFile(archiveDest)
  If $$$ISERR(sc) Return sc
  Set package.package = archive
  Set module = ##class(ZPM.PackageStorage).OpenDiskCharacter(manifestDest)
  If '$IsObject(module) Return $$$ERROR($$$GeneralError, "unable to open manifest on disk")
  Set package.manifest = module
  Set hash = $$$lcase(##class(%File).SHA1Hash(archiveDest, 1))
  Set package.hash = hash
  If ('silent) {
    Write !,"ArchiveSize: " _ archive.Size
    Write !,"ArchiveHash: " _ hash
  }
  Return package.%Save()
}

ClassMethod GetPackageNameFromRepositoryURL(url As %String) As %String
{
  Return $Piece(url, "/", *-1)
}

ClassMethod GetDefaultBranch(path As %String) As %String
{
  If ($Extract(path,$Length(path))="/") {
    Set path = $Extract(path,1,*-1)
  }
  Set branch = "main"
  Set ht = ##class(%Net.HttpRequest).%New()
  Set ht.Server = "api.github.com"
  Set ht.SSLConfiguration = ##class(ZPM.Utils).GetSSLConfiguration()
  Set ht.Https = 1
  Set ht.Location = "/repos"_path 
  $$$ThrowOnError(ht.Get())
  If (ht.HttpResponse.StatusCode=200) {
    Set jo = {}.%FromJSON(ht.HttpResponse.Data)
    Set branch = jo."default_branch" 
  }
  Return branch
}

ClassMethod FindModuleXmlUnder(root As %String) As %String [ Private ]
{
  Set moduleFile = ##class(%File).NormalizeFilename("module.xml", root)
  If ##class(%File).Exists(moduleFile) {
    Return moduleFile
  }
  Set rs = ##class(%File).FileSetFunc(root, 1)
  While rs.%Next() {
    If rs.Type'="D" Continue
    Set found = ..FindModuleXmlUnder(rs.Name)
    If found '= "" Return found
  }
  Return ""
}

/// Download the upstream archive and locate module.xml for metadata only (archive bytes are kept as-is).
ClassMethod DownloadPackageFromGitHub(url As %String, Output branch As %String, Output archivePath As %String, Output modulePath As %String, Output scratchDir As %String) As %Status
{
  Set archivePath = "", modulePath = "", scratchDir = ""
  Do ##class(%Net.URLParser).Parse(url, .tComponents)
  Set branch = ..GetDefaultBranch(tComponents("path"))
  Set ht = ##class(%Net.HttpRequest).%New()
  Set ht.Server = tComponents("host")
  If $Get(tComponents("scheme"))="https" {
    Set ht.SSLConfiguration = ##class(ZPM.Utils).GetSSLConfiguration()
    Set ht.Https = 1
  }
  If $Data(tComponents("port"), port), port'="" {
    Set ht.Port = port
  }
  Set ht.Location = tComponents("path")_"archive/"_branch_".tar.gz"
  Set tSC = ht.Get()
  If $$$ISERR(tSC) Return tSC
  If (ht.HttpResponse.StatusCode'=200) {
    Return $$$ERROR($$$GeneralError, "Unable to download repository "_url)
  }

  Set archivePath = ##class(%File).TempFilename("tgz")
  Set fs = ##class(%Stream.FileBinary).%New()
  Set fs.Filename = archivePath
  Do fs.CopyFromAndSave(ht.HttpResponse.Data)

  Set scratchDir = $$$FileTempDir
  Set res = $Zf(-100, "", "tar", "-zxvf", archivePath, "-C", scratchDir)
  Set modulePath = ..FindModuleXmlUnder(scratchDir)
  If modulePath = "" {
    Return $$$ERROR($$$GeneralError, "module.xml not found in downloaded repository archive")
  }
  Return $$$OK
}

ClassMethod GetModuleMeta(url As %String) As %DynamicObject
{
  Set jo = {"name":"", "version":""}
  Do ##class(%Net.URLParser).Parse(url, .tComponents)
  Set ht = ##class(%Net.HttpRequest).%New()
  Set ht.Server = "raw.githubusercontent.com"
  If $Get(tComponents("scheme"))="https" {
    Set ht.SSLConfiguration = ##class(ZPM.Utils).GetSSLConfiguration()
    Set ht.Https = 1
  }
  If $Data(tComponents("port"), port), port'="" {
    Set ht.Port = port
  }
  Set ht.Location = tComponents("path")_"master/module.xml"
  $$$ThrowOnError(ht.Get())
  If (ht.HttpResponse.StatusCode'=200) {
    $$$ThrowStatus($$$ERROR(5001,"Unable to download XML "_ht.Location))
  }

  Set xPathArray("Module/Version")=""
  Set xPathArray("Module/Name")=""
  $$$ThrowOnError(##class(ZPM.Utils).ReadXMLElements(ht.HttpResponse.Data, .xPathArray))

  Set jo.name = $Get(xPathArray("Module/Name","text"))
  Set jo.version = $Get(xPathArray("Module/Version","text"))
  
  Return jo
}

ClassMethod UpdatePackage(jo As %DynamicObject) As %Status
{
  Set outputFolder = ""
  Try {
    Set url = jo.repository
    If $Extract(url, *)'="/" {
      Set url = url _ "/"
    } 
    Set name = ..GetPackageNameFromRepositoryURL(url)
    Set meta = ..GetModuleMeta(url)
    If (meta.version = "") { $$$ThrowStatus($$$ERROR(5001, "Invalid package version")) }
    If (meta.name = "") { $$$ThrowStatus($$$ERROR(5001, "Package name is empty")) }
    Set tName = $$$lcase(meta.name)
    Set id = ""

    // ONE registry hosts every channel, so this upstream publish names the channel it
    // publishes into. Fail closed rather than guess: a wrong channel puts the artefact
    // in front of the wrong audience.
    Set channel = ""
    If jo.%IsDefined("channel") { Set channel = jo.%Get("channel") }
    If (channel = "") { $$$ThrowStatus($$$ERROR(5001, "channel is required")) }

    &sql(DELETE FROM ZPM.Package WHERE Name = :tName AND channel = :channel AND UpLink IS NOT NULL) // delete all "proxy" packages

    &sql(SELECT ID into :id FROM ZPM.Package WHERE name=:tName AND channel = :channel ORDER BY versionMajor DESC, versionMinor DESC, versionPatch DESC, versionPrerelease  DESC)
    If (id'="") { 
      If (..repositoryGetStored(id)'=url) { 
        $$$ThrowStatus($$$ERROR(5001, "Invalid repository for this Package"))
      } Else { 
        If (..NameChannelVersionExists(meta.name, channel, meta.version)) { 
          $$$ThrowStatus($$$ERROR(5001, "Version "_meta.version_" of Package "_meta.name_" is already published"))
        }
      	Set sc = ..Publish(url, name, channel)	
      }
    } Else {
      If (..RepositoryExists(url, .id)) {
	      $$$ThrowStatus($$$ERROR(5001, "This repository was published under a different name"))
      } Else {
        Set sc = ..Publish(url, name, channel)	
      }
    }
  } Catch ex {
    Set sc = ex.AsStatus() 
  }
  Return sc
}

ClassMethod Publish(url As %String, name As %String, channel As %String) As %Status
{
  Set archivePath = "", modulePath = "", scratchDir = ""
  Set tSC = ..DownloadPackageFromGitHub(url, .branch, .archivePath, .modulePath, .scratchDir)
  If $$$ISERR(tSC) Return tSC
  Set tSC = ..LoadPackageFromArchive(archivePath, modulePath, channel, url, 1)
  If scratchDir'="" {
    Do ##class(%File).RemoveDirectoryTree(scratchDir)
  }
  Return tSC
}

ClassMethod LoadFromGitHub(Url = "", channel As %String = "")
{
  If Url="" {
    Return ""
  }
  If $Extract(Url, *)'="/" { 
    Set Url = Url _ "/"
  }
  Set archivePath = "", modulePath = "", scratchDir = ""
  Set tSC = ..DownloadPackageFromGitHub(Url, .branch, .archivePath, .modulePath, .scratchDir)
  If $$$ISERR(tSC) {
    Do $System.OBJ.DisplayError(tSC)
  } Else {
    Set tSC = ..LoadPackageFromArchive(archivePath, modulePath, channel, Url)
    If $$$ISERR(tSC) {
      Do $System.OBJ.DisplayError(tSC)
    } Else {
      Write !,"Success"
    }
  }
  If scratchDir'="" {
    Do ##class(%File).RemoveDirectoryTree(scratchDir)
  }
}

/// returns latest versions of packages
/// 
/// `channel` is an optional FILTER: this is a listing, so browsing every channel is
/// legitimate as long as each row reports its own channel — which it does. Each
/// channel's "latest" is computed per (name, channel): the correlated subqueries below
/// match on channel as well as name, or a sprint build could be reported as develop's
/// latest.
ClassMethod GetLatest(searchTerms As %DynamicArray = "", manifest As %String = "", allVersions As %String = "", owner As %String = "", channel As %String = "", Output pStatus As %Status) As %DynamicArray
{
  Set pStatus = 1
  Set params = 1
  Set params(params) = owner

  If ( '($ClassName(searchTerms)="%Library.DynamicArray" ) || (searchTerms.%Size()=0) ) {
    // empty query
    Set searchCondition = " ( 1=1 ) "
  } Else {
    Set searchCondition = " ( "
    Set iter = searchTerms.%GetIterator()
    While iter.%GetNext(.key , .value ) {
      If (key=0) {
        Set searchCondition = searchCondition _ " ((p1.name %MATCHES ?) OR (p1.description %MATCHES ?) OR (p1.keywords %MATCHES ?)) "
      } Else {
        Set searchCondition = searchCondition _ " OR ((p1.name %MATCHES ?) OR (p1.description %MATCHES ?) OR (p1.keywords %MATCHES ?))"
      }
      Set params(params+1) = value
      Set params(params+2) = value
      Set params(params+3) = value
      Set params = params + 3
    }
    Set searchCondition = searchCondition_ " ) "
  }

  // Optional channel filter, appended last so its positional parameter follows the
  // search-term parameters (?s bind in textual order).
  If (channel '= "") {
    Set channelCondition = " AND p1.channel = ? "
  } Else {
    Set channelCondition = " "
  }

  Set sql = "SELECT p1.name, p1.channel, p1.repository, p1.description, p1.version, ul.Host, IFNULL( (SELECT TOP 1 1 FROM ZPM.Package p3 WHERE p1.name=p3.name AND p1.channel=p3.channel AND p3.owner = ? ORDER BY p3.versionMajor DESC, p3.versionMinor DESC, p3.versionPatch DESC, p3.versionPrerelease DESC, p3.versionBuildmetadata DESC ), 0, 1) as owner"_
            "  FROM ZPM.Package p1 "_
            "  LEFT JOIN ZPM.UpLink ul ON ul.ID = p1.UpLink " _
            "  WHERE (deleted = 0 OR deleted IS NULL) AND "_searchCondition_" "_ 
            " AND p1.version = ( SELECT TOP 1 version FROM ZPM.Package p2 WHERE p1.name=p2.name AND p1.channel=p2.channel ORDER BY p2.versionMajor DESC, p2.versionMinor DESC, p2.versionPatch DESC, p2.versionPrerelease DESC, p2.versionBuildmetadata DESC ) "
            _channelCondition

  If (channel '= "") {
    Set params(params+1) = channel
    Set params = params + 1
  }

  Set tStatement = ##class(%SQL.Statement).%New()
  Set tStatus = tStatement.%Prepare(sql)
  If ($$$ISERR(tStatus)) { 
    Set pStatus = tStatus
    Return []
  }
  Set tResult = tStatement.%Execute(params...)
  If (tResult.%SQLCODE<0) {
    Set pStatus = $$$ERROR(5001, "Error executing sql statement")
    Return []
  }
  Set tList = []
  While tResult.%Next() {
    Set tPkgInfo = {
      "name": (tResult.name),
      "channel": (tResult.channel),
      "description": (tResult.description),
      "repository": (tResult.repository),
      "origin": (tResult.Host),
      "versions": [(tResult.version)],
      "is_owner":(tResult.owner)
    }

    If (manifest = "1") {
      Set tPkgInfo.manifest = ""
      Set package = ##class(ZPM.Package).%OpenId(tResult.name_"||"_tResult.channel_"||"_tResult.version)
      Set manifestStream = package.GetManifestStream()
      If ($IsObject(manifestStream)) {
        While ('manifestStream.AtEnd) {
          Set tPkgInfo.manifest = tPkgInfo.manifest _ manifestStream.Read(100)
        }
      }
    }

    If (allVersions = "1") {
      Set tPkgInfo.allVersions = []
      Set sql2 = "SELECT version "_
            " FROM ZPM.Package "_
            " WHERE name = ? AND channel = ? AND (deleted = 0 OR deleted IS NULL) "_
            " ORDER BY versionMajor DESC, versionMinor DESC, versionPatch DESC, versionPrerelease DESC, versionBuildmetadata DESC"
      Set versionsResult = ##class(%SQL.Statement).%ExecDirect(, sql2, tResult.name, tResult.channel)
      While versionsResult.%Next() {
        Do tPkgInfo.allVersions.%Push(versionsResult.version)
      }
    }

    Do tList.%Push(tPkgInfo)
  }
  Return tList
}

Query ListLatest(searchTerm As %String = "") As %SQLQuery(ROWSPEC = "name:%String,channel:%String,description:%String,repository:%String,version:%String")
{
SELECT name, channel, repository, version, description 
FROM ZPM.Package p1
WHERE 
  version= (  
    SELECT TOP 1 version FROM ZPM.Package p2 WHERE p1.name=p2.name AND p1.channel=p2.channel 
    ORDER BY versionMajor DESC, versionMinor DESC, versionPatch DESC, versionPrerelease DESC, versionBuildmetadata DESC ) 
  AND (:searchTerm IS NULL OR (
     name %MATCHES :searchTerm
  OR description %MATCHES :searchTerm
  OR keywords %MATCHES :searchTerm)
)
GROUP BY name, channel
ORDER BY name, channel
}

/// Dry-run report for versions whose archive bytes still live only in <code>^ZPM.PackageS</code>.
/// Returns JSON: <code>{"onlyGlobal":n,"onDisk":n,"both":n,"onlyGlobalBytes":n,"rows":[...]}</code>.
ClassMethod DiskMigrationReport(Output pStatus As %Status) As %String
{
  Set pStatus = $$$OK
  Set out = {"onlyGlobal":0, "onDisk":0, "both":0, "onlyGlobalBytes":0, "rows":[]}
  Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT name, channel, version FROM ZPM.Package WHERE (deleted IS NULL OR deleted = 0) ORDER BY name, channel, version")
  If rs.%SQLCODE < 0 {
    Set pStatus = $$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message)
    Return out.%ToJSON()
  }
  While rs.%Next() {
    Set name = rs.name, ch = rs.channel, ver = rs.version
    Set onDisk = ##class(ZPM.PackageStorage).DiskArchiveExists(name, ch, ver)
    Set globalBytes = 0
    Set p = ..NameChannelVersionOpen(name, ch, ver, , .tSC)
    If $IsObject(p) && $IsObject(p.package) {
      Do p.package.Rewind()
      Set globalBytes = +p.package.Size
    }
    If onDisk && (globalBytes > 0) {
      Set out.both = out.both + 1
    } ElseIf onDisk {
      Set out.onDisk = out.onDisk + 1
    } ElseIf globalBytes > 0 {
      Set out.onlyGlobal = out.onlyGlobal + 1
      Set out.onlyGlobalBytes = out.onlyGlobalBytes + globalBytes
      Do out.rows.%Push({"name":(name), "channel":(ch), "version":(ver), "bytes":(globalBytes)})
    }
    Kill p
  }
  Return out.%ToJSON()
}

/// Copy global package streams to disk for up to <var>maxVersions</var> rows (0 = no cap).
/// <var>dryRun</var> defaults to 1. Verifies digest with <method>GetPackageHash</method> when <property>hash</property> is set.
ClassMethod MigrateDiskVersions(dryRun As %Boolean = 1, maxVersions As %Integer = 0, pkg As %String = "", channel As %String = "", version As %String = "", Output pStatus As %Status) As %String
{
  Set pStatus = $$$OK
  Set out = {"dryRun":(''dryRun), "migrated":0, "bytes":0, "remaining":0, "rows":[]}
  Set sql = "SELECT name, channel, version, hash FROM ZPM.Package WHERE (deleted IS NULL OR deleted = 0)"
  Set args = 0
  If pkg'="" Set sql = sql_" AND name = ?", args = args + 1, args(args) = pkg
  If channel'="" Set sql = sql_" AND channel = ?", args = args + 1, args(args) = channel
  If version'="" Set sql = sql_" AND version = ?", args = args + 1, args(args) = version
  Set sql = sql_" ORDER BY name, channel, versionMajor, versionMinor, versionPatch"
  Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, args...)
  If rs.%SQLCODE < 0 {
    Set pStatus = $$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message)
    Return out.%ToJSON()
  }
  Set n = 0, total = 0, remaining = 0
  While rs.%Next() {
    If (maxVersions > 0) && (n >= maxVersions) {
      Set remaining = remaining + 1
      Continue
    }
    Set name = rs.name, ch = rs.channel, ver = rs.version, expectedHash = rs.hash
    If ##class(ZPM.PackageStorage).DiskArchiveExists(name, ch, ver) Continue
    Set p = ..NameChannelVersionOpen(name, ch, ver, , .tSC)
    If '$IsObject(p) {
      Set pStatus = $$$ADDSC(pStatus, tSC)
      Continue
    }
    Set globalBytes = 0
    If $IsObject(p.package) {
      Do p.package.Rewind()
      Set globalBytes = +p.package.Size
    }
    If globalBytes = 0 {
      Kill p
      Continue
    }
    If 'dryRun {
      Set tSC = p.PersistStreamsToDisk()
      If $$$ISERR(tSC) {
        Set pStatus = $$$ADDSC(pStatus, tSC)
        Kill p
        Continue
      }
      Set diskStream = p.GetPackageStream()
      If (expectedHash '= "") && ($IsObject(diskStream)) {
        Set gotHash = ..GetPackageHash(diskStream)
        If gotHash '= expectedHash {
          Set pStatus = $$$ADDSC(pStatus, $$$ERROR($$$GeneralError, "hash mismatch after migrate for "_name_"@"_ver))
          Kill p
          Continue
        }
      }
      Set tSC = p.%Save()
      If $$$ISERR(tSC) {
        Set pStatus = $$$ADDSC(pStatus, tSC)
        Kill p
        Continue
      }
    }
    Set n = n + 1, total = total + globalBytes
    Do out.rows.%Push({"name":(name), "channel":(ch), "version":(ver), "bytes":(globalBytes)})
    Kill p
  }
  Set out.migrated = n, out.bytes = total, out.remaining = remaining
  Return out.%ToJSON()
}

/// After migrate, drop redundant <code>^ZPM.PackageS</code> chunks for rows that already have a verified on-disk archive.
/// <var>dryRun</var> defaults to 1.
ClassMethod ClearMigratedPackageGlobals(dryRun As %Boolean = 1, maxVersions As %Integer = 0, pkg As %String = "", channel As %String = "", version As %String = "", Output pStatus As %Status) As %String
{
  Set pStatus = $$$OK
  Set out = {"dryRun":(''dryRun), "cleared":0, "bytes":0, "remaining":0, "rows":[]}
  Set sql = "SELECT name, channel, version, hash FROM ZPM.Package WHERE (deleted IS NULL OR deleted = 0)"
  Set args = 0
  If pkg'="" Set sql = sql_" AND name = ?", args = args + 1, args(args) = pkg
  If channel'="" Set sql = sql_" AND channel = ?", args = args + 1, args(args) = channel
  If version'="" Set sql = sql_" AND version = ?", args = args + 1, args(args) = version
  Set sql = sql_" ORDER BY name, channel, versionMajor, versionMinor, versionPatch"
  Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, args...)
  If rs.%SQLCODE < 0 {
    Set pStatus = $$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message)
    Return out.%ToJSON()
  }
  Set n = 0, total = 0, remaining = 0
  While rs.%Next() {
    If (maxVersions > 0) && (n >= maxVersions) {
      Set remaining = remaining + 1
      Continue
    }
    Set name = rs.name, ch = rs.channel, ver = rs.version, expectedHash = rs.hash
    If '##class(ZPM.PackageStorage).DiskArchiveExists(name, ch, ver) Continue
    Set p = ..NameChannelVersionOpen(name, ch, ver, , .tSC)
    If '$IsObject(p) Continue
    Set globalBytes = 0
    If $IsObject(p.package) {
      Do p.package.Rewind()
      Set globalBytes = +p.package.Size
    }
    If globalBytes = 0 {
      Kill p
      Continue
    }
    Set diskStream = ##class(ZPM.PackageStorage).OpenDiskArchive(name, ch, ver)
    If '$IsObject(diskStream) {
      Kill p
      Continue
    }
    If (expectedHash '= "") && (..GetPackageHash(diskStream) '= expectedHash) {
      Kill p
      Continue
    }
    If 'dryRun {
      Set path = ##class(ZPM.PackageStorage).ArchivePath(name, ch, ver)
      Set fb = ##class(%Stream.FileBinary).%New()
      Set tSC = fb.LinkToFile(path)
      If $$$ISERR(tSC) {
        Set pStatus = $$$ADDSC(pStatus, tSC)
        Kill p
        Continue
      }
      Set p.package = fb
      Set tSC = p.%Save()
      If $$$ISERR(tSC) {
        Set pStatus = $$$ADDSC(pStatus, tSC)
        Kill p
        Continue
      }
    }
    Set n = n + 1, total = total + globalBytes
    Do out.rows.%Push({"name":(name), "channel":(ch), "version":(ver), "bytes":(globalBytes)})
    Kill p
  }
  Set out.cleared = n, out.bytes = total, out.remaining = remaining
  Return out.%ToJSON()
}

/// Hard purge: physically remove rows ALREADY soft-deleted (<code>deleted = 1</code>) by
/// <method>DeletePackageVersion</method>, together with their package tgz, manifest and
/// installer streams (<code>^ZPM.PackageS</code>) and their <code>dependencies</code> subnode.
/// <p>A soft delete only hides a version from IPM; its bytes stay in the database. This is the
/// step that actually frees space (the database file still needs compact + truncate to give
/// it back to the OS).
/// <ul>
/// <li><var>dryRun</var> (default 1): report only, delete nothing.</li>
/// <li><var>maxVersions</var>: cap rows purged per call (0 = no cap); bounds journal growth.</li>
/// <li><var>pkg</var> / <var>channel</var> / <var>version</var>: optional scope.</li>
/// </ul>
/// Idempotent: only <code>deleted = 1</code> rows are ever touched, so a re-run after a
/// partial run continues where it stopped and a run with nothing to do is a no-op.
/// Live rows (<code>deleted</code> 0 or NULL) are never selected.
/// <p>Returns a JSON string: <code>{"dryRun":..,"purged":n,"bytes":n,"remaining":n,"rows":[{"name","channel","version","bytes"}]}</code>.
ClassMethod PurgeDeleted(dryRun As %Boolean = 1, maxVersions As %Integer = 0, pkg As %String = "", channel As %String = "", Output pStatus As %Status, version As %String = "") As %String
{
  Set pStatus = $$$OK
  Set out = {"dryRun":(''dryRun), "purged":0, "bytes":0, "remaining":0, "rows":[]}
  Set sql = "SELECT name, channel, version FROM ZPM.Package WHERE deleted = 1"
  Set args = 0
  If pkg'="" Set sql = sql_" AND name = ?", args = args + 1, args(args) = pkg
  If channel'="" Set sql = sql_" AND channel = ?", args = args + 1, args(args) = channel
  If version'="" Set sql = sql_" AND version = ?", args = args + 1, args(args) = version
  Set sql = sql_" ORDER BY name, channel, versionMajor, versionMinor, versionPatch"
  Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, args...)
  If rs.%SQLCODE < 0 {
    Set pStatus = $$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message)
    Return out.%ToJSON()
  }
  Set n = 0, total = 0, remaining = 0
  While rs.%Next() {
    If (maxVersions > 0) && (n >= maxVersions) {
      Set remaining = remaining + 1
      Continue
    }
    Set name = rs.name, ch = rs.channel, ver = rs.version
    Set p = ..NameChannelVersionOpen(name, ch, ver, 0, .tSC)
    If '$IsObject(p) {
      Set pStatus = $$$ADDSC(pStatus, tSC)
      Continue
    }
    // re-check under the open: never purge a row that was revived since the SELECT
    If p.deleted '= 1 Continue
    Set bytes = 0
    Set diskBytes = ##class(ZPM.PackageStorage).DiskArchiveSize(name, ch, ver)
    Set:$IsObject(p.package) bytes = bytes + p.package.Size
    Set:$IsObject(p.manifest) bytes = bytes + p.manifest.Size
    Set:$IsObject(p.installer) bytes = bytes + p.installer.Size
    Set bytes = bytes + diskBytes
    Kill p
    If 'dryRun {
      Set tSC = ##class(ZPM.PackageStorage).DeleteVersionDirectory(name, ch, ver)
      If $$$ISERR(tSC) {
        Set pStatus = $$$ADDSC(pStatus, tSC)
        Continue
      }
      // %DeleteId removes the data node, the dependencies subnode, the index entries and
      // every stream property's ^ZPM.PackageS chunks.
      Set tSC = ..NameChannelVersionDelete(name, ch, ver)
      If $$$ISERR(tSC) {
        Set pStatus = $$$ADDSC(pStatus, tSC)
        Continue
      }
    }
    Set n = n + 1, total = total + bytes
    Do out.rows.%Push({"name":(name), "channel":(ch), "version":(ver), "bytes":(bytes)})
  }
  Set out.purged = n, out.bytes = total, out.remaining = remaining
  Return out.%ToJSON()
}

Storage Default
{
<Data name="PackageDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>owner</Value>
</Value>
<Value name="3">
<Value>description</Value>
</Value>
<Value name="4">
<Value>keywords</Value>
</Value>
<Value name="5">
<Value>license</Value>
</Value>
<Value name="6">
<Value>homePage</Value>
</Value>
<Value name="7">
<Value>repository</Value>
</Value>
<Value name="8">
<Value>package</Value>
</Value>
<Value name="9">
<Value>hash</Value>
</Value>
<Value name="10">
<Value>manifest</Value>
</Value>
<Value name="11">
<Value>size</Value>
</Value>
<Value name="12">
<Value>installer</Value>
</Value>
<Value name="13">
<Value>versionMajor</Value>
</Value>
<Value name="14">
<Value>versionMinor</Value>
</Value>
<Value name="15">
<Value>versionPatch</Value>
</Value>
<Value name="16">
<Value>versionLabel</Value>
</Value>
<Value name="17">
<Value>versionPrerelease</Value>
</Value>
<Value name="18">
<Value>versionBuildmetadata</Value>
</Value>
<Value name="19">
<Value>UpLink</Value>
</Value>
<Value name="20">
<Value>publishTS</Value>
</Value>
<Value name="21">
<Value>deployed</Value>
</Value>
<Value name="22">
<Value>platformVersion</Value>
</Value>
<Value name="23">
<Value>deleted</Value>
</Value>
</Data>
<Data name="dependencies">
<Attribute>dependencies</Attribute>
<Structure>subnode</Structure>
<Subscript>"dependencies"</Subscript>
</Data>
<DataLocation>^ZPM.PackageD</DataLocation>
<DefaultData>PackageDefaultData</DefaultData>
<IdLocation>^ZPM.PackageD</IdLocation>
<IndexLocation>^ZPM.PackageI</IndexLocation>
<StreamLocation>^ZPM.PackageS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
